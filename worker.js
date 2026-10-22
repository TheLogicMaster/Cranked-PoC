// Browser front end, optional worker mode (?worker=1): the engine (engine.js) off the page's thread
"use strict";
importScripts("cranked.js", "engine.js");
onmessage = createCrankedEngine((msg, transfer) => postMessage(msg, transfer), true);
