(function(d){var h=[];d.loadImages=function(a,e){"string"==typeof a&&(a=[a]);for(var f=a.length,g=0,b=0;b<f;b++){var c=document.createElement("img");c.onload=function(){g++;g==f&&d.isFunction(e)&&e()};c.src=a[b];h.push(c)}}})(window.jQuery);
$.fn.hasAttr = function(name) { var attr = $(this).attr(name); return typeof attr !== typeof undefined && attr !== false; };


$(document).ready(function() {
r=function(){dpi=window.devicePixelRatio;$('.js10').attr('src', (dpi>1) ? ((dpi>2) ? 'images/iu-240.png' : 'images/iu-160.png') : 'images/iu-80.png');
$('.js').attr('src', (dpi>1) ? 'images/background-2400.png' : 'images/background-1200.png');
$('.js2').attr('src', (dpi>1) ? ((dpi>2) ? 'images/ipadoutline-177.png' : 'images/ipadoutline-118.png') : 'images/ipadoutline-59.png');
$('.js3').attr('src', (dpi>1) ? ((dpi>2) ? 'images/iphoneoutline-117.png' : 'images/iphoneoutline-78.png') : 'images/iphoneoutline-39.png');
$('.js4').attr('src', (dpi>1) ? ((dpi>2) ? 'images/watchoutline-99.png' : 'images/watchoutline-66.png') : 'images/watchoutline-33.png');
$('.js5').attr('src', (dpi>1) ? ((dpi>2) ? 'images/imacoutline-180.png' : 'images/imacoutline-120.png') : 'images/imacoutline-60.png');
$('.js6').attr('src', (dpi>1) ? ((dpi>2) ? 'images/macbookoutline-180.png' : 'images/macbookoutline-120.png') : 'images/macbookoutline-60.png');
$('.js7').attr('src', (dpi>1) ? ((dpi>2) ? 'images/ipadscreenshot-1227.png' : 'images/ipadscreenshot-818.png') : 'images/ipadscreenshot-409.png');
$('.js8').attr('src', (dpi>1) ? ((dpi>2) ? 'images/iphonescreenshot-426.png' : 'images/iphonescreenshot-284.png') : 'images/iphonescreenshot-142.png');
$('.js9').attr('src', (dpi>1) ? ((dpi>2) ? 'images/watchscreenshot-300.png' : 'images/watchscreenshot-200.png') : 'images/watchscreenshot-100.png');};
if(!window.HTMLPictureElement){r();}
(function(){$('a[href^="#"]:not(.allowConsent,.noConsent,.denyConsent,.removeConsent)').each(function(i,e){$(e).click(function(){var t=e.hash.length>1?$('[name="'+e.hash.slice(1)+'"]').offset().top:0;return $("html, body").animate({scrollTop:t},400),!1})})})();

});