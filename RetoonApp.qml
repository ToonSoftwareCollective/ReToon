//
// ReToon: sets up and starts ReToon from the original Toon software, on a
// Toon 2 or a Toon 1 (isNxt tells them apart).
// The work is done by retoon.sh in this folder, which the "tsc" helper runs
// as root when "external-retoon" is written to /tmp/tsc.command.
//

import QtQuick 2.1
import qb.components 1.0
import qb.base 1.0

App {
	id: retoonApp

	property url tileUrl: "RetoonTile.qml"
	property url retoonScreenUrl: "RetoonScreen.qml"
	property url thumbnailIcon: "qrc:/tsc/refresh.png"

	// what retoon.sh last reported: idle, needed, ready, working, restarting, error
	property string setupState: "idle"
	property string setupText: ""
	property int setupStep: 0
	property int setupSteps: 7
	// when the install was asked for (ms), 0 = not waiting for it to start
	property double installAsked: 0
	// the status file as last read, and as it was when the install was asked for
	property string lastStatus: ""
	property string staleStatus: ""

	function init() {
		registry.registerWidget("tile", tileUrl, this, null, {thumbLabel: "ReToon", thumbIcon: thumbnailIcon, thumbCategory: "general", thumbWeight: 30, baseTileWeight: 10, baseTileSolarWeight: 10, thumbIconVAlignment: "center"});
		registry.registerWidget("screen", retoonScreenUrl, this, null, {lazyLoadScreen: true});
	}

	function writeFile(path, text) {
		var f = new XMLHttpRequest();
		f.open("PUT", "file://" + path);
		f.send(text);
	}

	// what: "check", "install" or "cleanup" (Toon 1)
	function request(what) {
		if (what !== "check") {
			setupState = "working";
			setupText = "Starting...";
			installAsked = Date.now();
			staleStatus = lastStatus;
		}
		// retoon.sh checks for itself too; both must agree
		writeFile("/tmp/retoon.board", isNxt ? "toon2" : "toon1");
		writeFile("/tmp/retoon.request", what);
		writeFile("/tmp/tsc.command", "external-retoon");
		statusTimer.start();
	}

	function readStatus() {
		var f = new XMLHttpRequest();
		f.onreadystatechange = function() {
			if (f.readyState !== XMLHttpRequest.DONE || !f.responseText)
				return;
			try {
				var s = JSON.parse(f.responseText);
				// The helper takes a few seconds to start the script. Until
				// then the file still holds what it held before the button
				// was pressed (the last check, or an earlier error): showing
				// that would bring the button back as if nothing had happened.
				if (installAsked > 0) {
					if (f.responseText === staleStatus && Date.now() - installAsked < 30000)
						return;
					installAsked = 0;
				}
				lastStatus = f.responseText;
				setupState = s.state;
				setupText = s.text;
				setupStep = s.step;
				setupSteps = s.steps;
			} catch (e) {
				// half-written: the next round reads it whole
			}
		}
		f.open("GET", "file:///tmp/retoon.status");
		f.send();
	}

	Timer {
		id: statusTimer
		interval: 2000
		repeat: true
		onTriggered: readStatus()
	}
}
