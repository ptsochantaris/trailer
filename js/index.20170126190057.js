(function(d){var h=[];d.loadImages=function(a,e){"string"==typeof a&&(a=[a]);for(var f=a.length,g=0,b=0;b<f;b++){var c=document.createElement("img");c.onload=function(){g++;g==f&&d.isFunction(e)&&e()};c.src=a[b];h.push(c)}}})(window.jQuery);
$.fn.hasAttr = function(name) { var attr = $(this).attr(name); return typeof attr !== typeof undefined && attr !== false; };


$(document).ready(function() {
r=function(){dpi=window.devicePixelRatio;$('.js').attr('src', (dpi>1) ? 'images/background-2400-1.png' : 'images/background-1200-1.png');
$('.js-2').attr('src', (dpi>1) ? ((dpi>2) ? 'images/imacoutline-180.png' : 'images/imacoutline-120.png') : 'images/imacoutline-60.png');
$('.js-3').attr('src', (dpi>1) ? ((dpi>2) ? 'images/macbookoutline-180-1.png' : 'images/macbookoutline-120-1.png') : 'images/macbookoutline-60-1.png');
$('.js-4').attr('src', (dpi>1) ? ((dpi>2) ? 'images/ipadoutline-177-1.png' : 'images/ipadoutline-118-1.png') : 'images/ipadoutline-59-1.png');
$('.js-5').attr('src', (dpi>1) ? ((dpi>2) ? 'images/iphoneoutline-117-1.png' : 'images/iphoneoutline-78-1.png') : 'images/iphoneoutline-39-1.png');
$('.js-6').attr('src', (dpi>1) ? ((dpi>2) ? 'images/watchoutline-99-1.png' : 'images/watchoutline-66-1.png') : 'images/watchoutline-33-1.png');
$('.js-7').attr('src', (dpi>1) ? ((dpi>2) ? 'images/ipadscreenshot-1227.png' : 'images/ipadscreenshot-818.png') : 'images/ipadscreenshot-409.png');
$('.js-8').attr('src', (dpi>1) ? ((dpi>2) ? 'images/iphonescreenshot-425.png' : 'images/iphonescreenshot-283.png') : 'images/iphonescreenshot-142-1.png');
$('.js-9').attr('src', (dpi>1) ? ((dpi>2) ? 'images/watchscreenshot-300.png' : 'images/watchscreenshot-200.png') : 'images/watchscreenshot-100.png');};
if(!window.HTMLPictureElement){r();}

});