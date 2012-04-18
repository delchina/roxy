(:
Copyright 2012 MarkLogic Corporation

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
:)
xquery version "1.0-ml";

module namespace router = "http://marklogic.com/roxy/router";

import module namespace ch = "http://marklogic.com/roxy/controller-helper" at "/roxy/lib/controller-helper.xqy";
import module namespace config = "http://marklogic.com/roxy/config" at "/app/config/config.xqy";
import module namespace req = "http://marklogic.com/roxy/request" at "/roxy/lib/request.xqy";
import module namespace rh = "http://marklogic.com/roxy/routing-helper" at "/roxy/lib/routing-helper.xqy";
import module namespace u = "http://marklogic.com/roxy/util" at "/roxy/lib/util.xqy";

declare option xdmp:mapping "false";

declare variable $controller as xs:QName := req:get("controller", "type=xs:QName");
declare variable $controller-path as xs:string := fn:concat("/app/controllers/", $controller, ".xqy");
declare variable $func as xs:string := req:get("func", "main", "type=xs:string");
declare variable $format as xs:string := req:get("format", $config:DEFAULT-FORMAT, "type=xs:string");
declare variable $default-view as xs:string := fn:concat($controller, "/", $func);

(: assume no default layout for xml, json, text :)
declare variable $default-layout as xs:string? := map:get($config:DEFAULT-LAYOUTS, $format);

declare function router:route()
{
	let $function-qname := 
		xdmp:with-namespaces(
			("c", fn:concat("http://marklogic.com/roxy/controller/", $controller)),
			xs:QName(fn:concat("c:", $func)))

	let $validate-function :=
		if (u:module-file-exists($controller-path) and
				u:function-exists($function-qname, $controller-path)) then ()
		else
			fn:error(xs:QName("four-o-four"))

	(: run the function :)
	let $data := xdmp:apply(xdmp:function($function-qname, $controller-path))

(:	let $data :=
	  try
	  {
	  	xdmp:apply(xdmp:function($function-qname, $controller-path))
	  }
	  catch($ex)
	  {
	    if (($ex/error:code = "XDMP-UNDFUN" and $ex/error:data/error:datum = fn:concat($func, "()")) or
	        ($ex/error:code = ("SVC-FILOPN", "XDMP-MODNOTFOUND") and $ex/error:data/error:datum/fn:ends-with(., $controller-path))) then
	      fn:error(xs:QName("four-o-four"))
	    else
	      xdmp:rethrow()
	  }:)

	(: Roxy options :)
	let $options :=
	  for $key in map:keys($ch:map)
	  where fn:starts-with($key, "ch:config-")
	  return
	    map:get($ch:map, $key)

	(: remove options from the data :)
	let $_ :=
	  for $key in map:keys($ch:map)
	    where fn:starts-with($key, "ch:config-")
	    return
	    map:delete($ch:map, $key)

	let $format as xs:string := ($options[self::ch:config-format][ch:formats/ch:format = $format]/ch:format, $format)[1]
	let $_ := rh:set-content-type($format)

	(: controller override of the view :)
	let $view := ($options[self::ch:config-view][ch:formats/ch:format = $format]/ch:view, $default-view)[1][. ne ""]

	(: controller override of the layout :)
	let $layout :=
	  if (fn:exists($options[self::ch:config-layout][ch:formats/ch:format = $format])) then
	    $options[self::ch:config-layout][ch:formats/ch:format = $format]/ch:layout[. ne ""]
	  else
	    $default-layout

	(: if the view return something other than the map or () then bypass the view and layout :)
	let $bypass as xs:boolean := fn:exists($data) and fn:not($data instance of map:map)

	return
	  if (fn:not($bypass) and (fn:exists($view) or fn:exists($layout))) then
	    let $view-result :=
	      if (fn:exists($ch:map) and fn:exists($view)) then
	        rh:render-view($view, $format, $ch:map)
	      else
	        ()
	    return
	      if (fn:not($bypass) and fn:exists($layout)) then
	        let $_ :=
	          if (fn:exists($view-result) and
	          		fn:not($view-result instance of map:map) and
	          		fn:not(fn:deep-equal(document {$ch:map}, document {$view-result}))) then
	            map:put($ch:map, "view", $view-result)
	          else
	            map:put($ch:map, "view",
	              for $key in map:keys($ch:map)
	              return
	                map:get($ch:map, $key))
	        return
	          rh:render-layout($layout, $format, $ch:map)
	      else
	        $view-result
	  else if (fn:not($bypass)) then
	    for $key in map:keys($ch:map)
	    return
	      map:get($ch:map, $key)
	  else
	    $data
};