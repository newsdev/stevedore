(function(){
var cssId = 'legacy-zam5nzz'; 
if (! document.getElementById(cssId)) {
    var head   = document.getElementsByTagName('head')[0];
    var link   = document.createElement('link');
    link.id    = cssId;
    link.rel   = 'stylesheet';
    link.type  = 'text/css';
    link.href  = 'https://typeface.nytimes.com/css/zam5nzz.css';
    link.media = 'all';
    head.appendChild(link);
}
document.documentElement.className = document.documentElement.className.replace( 'wf-loading', 'wf-active');
})();
