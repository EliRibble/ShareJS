exports.content = '
<!DOCTYPE html>
<html>
 <head>
  <meta charset="UTF-8">
  <title>ShareJS Same-Origin Bypass</title>
  <script src="//ajax.googleapis.com/ajax/libs/jquery/2.0.3/jquery.min.js"></script>
  <script type="text/javascript">
    function loaded() {
        if(window.addEventListener) {
            addEventListener("message", listener, false);
        } else {
            attachEvent("onmessage", listener);
        }
    }
    function listener(event) {
        if(event.data.action == "get") {
            $.get({
                url     : event.data.url,
                success : function(data) {
                    event.source.postMessage({
                        from    : "sharejs",
                        url     : event.data.url,
                        data    : data
                    }, event.origin);
                }
            });
        }
    }
  </script>
 </head>
 <body onload="loaded()">
    <div id="test"></div>
 </body>
</html>'
