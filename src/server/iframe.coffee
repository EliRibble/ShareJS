exports.content = '
<!DOCTYPE html>
<html>
 <head>
  <meta charset="UTF-8">
  <meta http-equiv="X-UA-Compatible" content="IE=8" />
  <title>ShareJS Same-Origin Bypass</title>
  <script>
    function _stripSubdomain(url){
        var a = document.createElement("a");
        a.href = url;
        hostOnly = a.host.split(":")[0];
        return hostOnly.substr(hostOnly.indexOf(".") + 1);
    }
    var base_domain = _stripSubdomain(window.location.href);
    document.domain = base_domain;
    if(typeof console != "undefined" && typeof console.log != "undefined"){
        console.log("ShareJS iframe set domain to " + base_domain);
    }
  </script>
  <script src="../channel/bcsocket.js"></script>
  <script src="../share/share.uncompressed.js"></script>
  <script src="../share/json.js"></script>
  <script src="../share/cm.js"></script>
 </head>
 <body>
    <h1>IFrame for cross-domain support.</h1>
 </body>
</html>'
