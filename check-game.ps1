$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HyperLaunchJs {
  [DllImport("Chakra.dll")] static extern int JsCreateRuntime(uint attributes, IntPtr callback, out IntPtr runtime);
  [DllImport("Chakra.dll")] static extern int JsCreateContext(IntPtr runtime, out IntPtr context);
  [DllImport("Chakra.dll")] static extern int JsSetCurrentContext(IntPtr context);
  [DllImport("Chakra.dll", CharSet=CharSet.Unicode)] static extern int JsRunScript(string script, UIntPtr cookie, string url, out IntPtr result);
  [DllImport("Chakra.dll")] static extern int JsGetAndClearException(out IntPtr exception);
  [DllImport("Chakra.dll")] static extern int JsConvertValueToString(IntPtr value, out IntPtr text);
  [DllImport("Chakra.dll")] static extern int JsStringToPointer(IntPtr text, out IntPtr value, out UIntPtr length);
  [DllImport("Chakra.dll")] static extern int JsDisposeRuntime(IntPtr runtime);
  static string Read(IntPtr value) { IntPtr text, chars; UIntPtr length; JsConvertValueToString(value, out text); JsStringToPointer(text, out chars, out length); return Marshal.PtrToStringUni(chars, (int)length.ToUInt64()); }
  public static string Run(string script) {
    IntPtr runtime, context, result;
    int code = JsCreateRuntime(0, IntPtr.Zero, out runtime);
    if (code != 0) throw new Exception("JS runtime: " + code);
    try {
      JsCreateContext(runtime, out context); JsSetCurrentContext(context);
      code = JsRunScript(script, UIntPtr.Zero, "hyperlaunch-check.js", out result);
      if (code != 0) { JsGetAndClearException(out result); throw new Exception("JavaScript: " + Read(result) + " (" + code + ")"); }
      return Read(result);
    } finally { JsSetCurrentContext(IntPtr.Zero); JsDisposeRuntime(runtime); }
  }
}
'@
$source = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'index.html'))
$script = [regex]::Match($source, '(?s)<script>(.*?)</script>').Groups[1].Value
if (-not $script) { throw 'Game script missing' }
$mock = @'
var results = [], draws = 0, marks = 0, storage = {}, listeners = {}, elements = {};
function check(value, label) { if (!value) throw new Error(label); results.push(label); }
var context = {};
"save restore translate rotate scale setTransform clearRect fillRect strokeRect beginPath arc ellipse moveTo lineTo bezierCurveTo quadraticCurveTo closePath fill stroke clip rect roundRect".split(" ").forEach(function(k) { context[k] = function() { if(k === 'fill' && arguments.length) marks++; }; });
context.createRadialGradient = context.createLinearGradient = function() { return {addColorStop:function(){}}; };
context.drawImage = function() { draws++; };
context.fillText = function(){};
context.measureText = function() { return {width:90}; };
function element(id) { return elements[id] || (elements[id] = { hidden:id==='game'||id==='ovOver', value:'', textContent:'', innerHTML:'', style:{}, listeners:{}, focus:function(){}, addEventListener:function(k,f){this.listeners[k]=f;}, getBoundingClientRect:function(){return {left:200,top:100,width:40,height:30};}, getContext:function(){return context;} }); }
var document = {addEventListener:function(k,f){listeners[k]=f;},getElementById:element,querySelector:function(){return {getAttribute:function(){return 'M7 21 C7 14 9 12 11 13Z';}};},createElement:function(){return {textContent:'',innerHTML:''};},body:{classList:{add:function(){},remove:function(){}}},documentElement:{}};
var window = {innerWidth:390,innerHeight:844,devicePixelRatio:1,addEventListener:function(k,f){listeners[k]=f;}};
var localStorage = {getItem:function(k){return storage[k] || null;},setItem:function(k,v){storage[k]=v;}};
function getComputedStyle(){return {paddingTop:0,paddingRight:0,paddingBottom:0,paddingLeft:0};}
function setTimeout(fn){fn();}
function requestAnimationFrame(){}
function Path2D(){}
function Image(){Object.defineProperty(this,'src',{set:function(){this.onload();}});}
'@
$suite = @'
  check(spriteReady && !$('btnPlay').disabled, 'Sprite loads and enables Play');
  drawHero(1000); check(draws > 0 && marks > 0, 'Hero draws new sprite and branded coin paths');
  openGame(); check(!gameEl.hidden && state === 'ready', 'Play opens game');
  $('nick').value = 'x'; tryStart(); check(state === 'ready', 'Short nick rejected');
  $('nick').value = 'pilot'; tryStart(); check(state === 'timing', 'Valid nick starts launch meter');
  drawGame(); launch(); check(state === 'flying' && launchMult === 1.45, 'Perfect launch starts flight');
  fuel = 50; objs = [{k:'coin',x:rocket.x,y:rocket.y-6,r:16}]; update(0.016);
  check(fuel > 61 && fuel < 62 && objs.length === 0, 'Fuel coin collects and restores 12 percent');
  check(coins === 1 && rings.length === 1 && pickupFlights.length === 1 && pickupPulse > 0, 'Collection creates counter, expanding ring and flying coin');
  check($('pickupNotice').textContent.indexOf('COIN COLLECTED') === 0, 'Collection has explicit visible confirmation');
  drawGame(); check($('hudCoins').textContent === 1 && !$('flightHud').hidden, 'Flight HUD displays collected coins');
  var pauseFuel = fuel, pauseAltitude = meters, pauseAge = pickupFlights[0].age;
  togglePause(); update(2); check(fuel === pauseFuel && meters === pauseAltitude && pickupFlights[0].age === pauseAge, 'Pause freezes fuel, movement and collection effects');
  var pausedTarget = rocket.tx; gcv.listeners.pointermove({clientX:0}); check(rocket.tx === pausedTarget, 'Paused flight ignores pointer movement');
  togglePause(); check(!paused && $('ovPause').hidden, 'Resume returns to flight');
  objs = [{k:'rock',x:rocket.x,y:rocket.y-6,r:19,vx:0,rot:0,vr:0,seed:0}]; update(0.016);
  check(fuel > 37 && fuel < 38, 'Meteor removes 24 percent fuel');
  var protectedFuel = fuel; objs = [{k:'rock',x:rocket.x,y:rocket.y-6,r:19,vx:0,rot:0,vr:0,seed:0}]; update(0.016);
  check(fuel > protectedFuel - 1 && hitShield > 0, 'Recovery shield prevents repeated meteor damage');
  objs = [{k:'bolt',x:rocket.x,y:rocket.y-6,r:17}]; update(0.016);
  check(boostT > 2.7, 'Boost activates'); drawGame();
  var beforeMove = rocket.x; keys.r = true; update(0.1); keys.r = false;
  check(rocket.x > beforeMove, 'Keyboard movement works');
  objs = [{k:'coin',x:rocket.x+75,y:rocket.y-6,r:20}]; var magnetX = objs[0].x; update(0.016);
  check(objs[0].x < magnetX, 'Nearby fuel coins are pulled toward the rocket');
  fuel = 99; collectCoin({x:rocket.x,y:rocket.y}); check(fuel === 100 && $('pickupNotice').textContent.indexOf('+1% FUEL') >= 0, 'Near-full tank reports actual fuel gained');
  collectCoin({x:rocket.x,y:rocket.y}); check(fuel === 100 && $('pickupNotice').textContent.indexOf('TANK FULL') >= 0, 'Full tank never overflows or shows false fuel gain');
  check(bestStreak >= 2, 'Consecutive pickups build a streak');
  objs = []; spawnCount = 0; var originalRandom = Math.random;
  Math.random = function(){return 0.15;}; spawn();
  Math.random = function(){return 0.8;}; spawn();
  Math.random = originalRandom;
  check(objs.length === 2 && objs[0].k === 'coin' && objs[1].k === 'rock', 'Single fuel pickups and meteors spawn independently');
  check(objs[0].x !== objs[1].x && objs.every(function(o){return o.x >= CX-HALF+40 && o.x <= CX+HALF-40;}), 'Spawn positions scatter across reachable flight space');
  update(4.1); check(streak === 0 && rings.length === 0 && pickupFlights.length === 0, 'Streak and pickup effects expire cleanly');
  window.innerWidth = 1440; window.innerHeight = 900; resize(); drawGame();
  check(W > 1000 && isFinite(rocket.x), 'Desktop canvas resizes');
  window.innerWidth = 320; window.innerHeight = 568; resize(); drawGame();
  check(rocket.x >= CX-HALF+34 && rocket.x <= CX+HALF-34, 'Small mobile screen keeps rocket in movement bounds');
  fuel = 0.001; update(0.016); check(state === 'over' && !ovOver.hidden, 'Fuel exhaustion ends run');
  check(localBoard().length === 1, 'Result saved locally');
  startTiming(); check(state === 'timing' && fuel === 100, 'Replay resets game');
  keys.l = true; listeners.blur(); check(!keys.l, 'Focus loss clears movement');
  check(paused && !$('ovPause').hidden, 'Leaving the window automatically pauses the run');
  closeGame(); check(gameEl.hidden, 'Exit returns to landing');
  results.push('CHECKS PASSED: ' + results.length);
'@
$end = $script.LastIndexOf('})();')
if ($end -lt 0) { throw 'Game closure missing' }
$instrumented = $script.Insert($end, $suite)
[HyperLaunchJs]::Run($mock + "`n" + $instrumented + "`nresults.join('\n');")

$ids = [regex]::Matches($source, '\bid="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
$duplicates = $ids | Group-Object | Where-Object Count -gt 1
if ($duplicates) { throw 'Duplicate HTML IDs' }
foreach ($match in [regex]::Matches($source, '(?:src|href)="([^"#]+)"')) {
  $reference = $match.Groups[1].Value
  if ($reference -notmatch '^(https?:|data:)' -and -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $reference))) { throw "Missing asset: $reference" }
}
Write-Output 'HTML IDs and local asset references: PASS'
if ($source -match '[\u0400-\u04ff]') { throw 'Untranslated Cyrillic text remains' }
if ($source -match 'brand-banner|hyperlaunch-banner') { throw 'Banner still embedded in site' }
if ($source -notmatch 'class="brand-avatar"' -or $source -notmatch 'lang="en"') { throw 'English page or rocket avatar missing' }
Write-Output 'English copy, removed banner, and rocket avatar: PASS'
