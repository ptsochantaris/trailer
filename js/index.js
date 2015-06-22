(function(d){var h=[];d.loadImages=function(a,e){"string"==typeof a&&(a=[a]);for(var f=a.length,g=0,b=0;b<f;b++){var c=document.createElement("img");c.onload=function(){g++;g==f&&d.isFunction(e)&&e()};c.src=a[b];h.push(c)}}})(window.jQuery||window.Zepto);
 $.fn.hasAttr = function(name) { var attr = $(this).attr(name); return typeof attr !== typeof undefined && attr !== false; };

$(document).ready(function() {
r = function() {
$('.img').attr('src', (window.devicePixelRatio > 1) ? ((window.devicePixelRatio > 2) ? 'images/background-3600.png' : 'images/background-2400.png') : 'images/background-1200.png');
$('.img-2').attr('src', (window.devicePixelRatio > 1) ? ((window.devicePixelRatio > 2) ? 'images/imacoutline-180.png' : 'images/imacoutline-120.png') : 'images/imacoutline-60.png');
$('.img-3').attr('src', (window.devicePixelRatio > 1) ? ((window.devicePixelRatio > 2) ? 'images/macbookoutline-180.png' : 'images/macbookoutline-120.png') : 'images/macbookoutline-60.png');
$('.img-4').attr('src', (window.devicePixelRatio > 1) ? ((window.devicePixelRatio > 2) ? 'images/ipadoutline-177.png' : 'images/ipadoutline-118.png') : 'images/ipadoutline-59.png');
$('.img-5').attr('src', (window.devicePixelRatio > 1) ? ((window.devicePixelRatio > 2) ? 'images/iphoneoutline-117.png' : 'images/iphoneoutline-78.png') : 'images/iphoneoutline-39.png');
$('.img-6').attr('src', (window.devicePixelRatio > 1) ? ((window.devicePixelRatio > 2) ? 'images/watchoutline-99.png' : 'images/watchoutline-66.png') : 'images/watchoutline-33.png');
$('.img-7').attr('src', (window.devicePixelRatio > 1) ? ((window.devicePixelRatio > 2) ? 'images/ipadscreenshot-1230.png' : 'images/ipadscreenshot-820.png') : 'images/ipadscreenshot-410.png');
$('.img-8').attr('src', (window.devicePixelRatio > 1) ? ((window.devicePixelRatio > 2) ? 'images/iphonescreenshot-426.png' : 'images/iphonescreenshot-284.png') : 'images/iphonescreenshot-142.png');
$('.img-9').attr('src', (window.devicePixelRatio > 1) ? ((window.devicePixelRatio > 2) ? 'images/watchscreenshot-300.png' : 'images/watchscreenshot-200.png') : 'images/watchscreenshot-100.png');};
$(window).resize(r);
r();

});