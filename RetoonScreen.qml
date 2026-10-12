//
// ReToon setup screen: says what is there, and one button that puts
// everything in place and restarts the Toon into ReToon.
//

import QtQuick 2.1
import qb.components 1.0

Screen {
	id: retoonScreen

	screenTitle: "ReToon"

	property bool busy: app.setupState === "working" || app.setupState === "restarting"

	onShown: app.request("check")

	Text {
		id: intro
		anchors {
			top: parent.top
			topMargin: isNxt ? 40 : 32
			left: parent.left
			leftMargin: isNxt ? 60 : 48
			right: parent.right
			rightMargin: anchors.leftMargin
		}
		font {
			family: qfont.regular.name
			pixelSize: isNxt ? 22 : 18
		}
		color: "#565656"
		wrapMode: Text.WordWrap
		text: "ReToon turns this Toon into an open wall panel and thermostat that works with Home Assistant. " +
		      "It is installed next to the original software: nothing is removed, and you can come back here " +
		      "from the ReToon web interface (Settings, System, Starting up).\n\n" +
		      "The button below puts ReToon in place, takes over the WiFi settings of this Toon and restarts it. " +
		      "After the restart the address of the web interface is shown on the screen (tap the Home Assistant icon)."
	}

	Text {
		id: statusLine
		anchors {
			top: intro.bottom
			topMargin: isNxt ? 30 : 24
			left: intro.left
			right: intro.right
		}
		font {
			family: qfont.semiBold.name
			pixelSize: isNxt ? 24 : 19
		}
		color: app.setupState === "error" ? "#c0392b" : "#303030"
		wrapMode: Text.WordWrap
		text: app.setupText === "" ? "Looking at what is on this Toon..." :
		      (retoonScreen.busy && app.setupStep > 0 ? "Step " + app.setupStep + " of " + app.setupSteps + ": " : "") + app.setupText
	}

	StandardButton {
		id: goButton
		text: app.setupState === "ready" ? "Start ReToon" : "Install and start ReToon"
		height: isNxt ? 50 : 40
		enabled: !retoonScreen.busy && (app.setupState === "ready" || app.setupState === "needed" || app.setupState === "error")
		anchors {
			top: statusLine.bottom
			topMargin: isNxt ? 30 : 24
			left: intro.left
		}
		topClickMargin: 2
		onClicked: app.request("install")
	}
}
