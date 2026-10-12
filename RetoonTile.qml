//
// ReToon tile: opens the setup screen
//

import QtQuick 2.1
import qb.components 1.0

Tile {
	id: retoonTile
	property bool dimState: screenStateController.dimmedColors

	onClicked: stage.openFullscreen(app.retoonScreenUrl)

	Text {
		id: nameText
		text: "ReToon"
		color: dimmableColors.clockTileColor
		anchors {
			horizontalCenter: parent.horizontalCenter
			verticalCenter: parent.verticalCenter
			verticalCenterOffset: isNxt ? -16 : -12
		}
		font.pixelSize: isNxt ? 44 : 34
		font.family: qfont.bold.name
	}

	Text {
		text: "Tap to set up and start"
		color: dimmableColors.clockTileColor
		visible: !dimState
		anchors {
			top: nameText.bottom
			topMargin: isNxt ? 6 : 4
			horizontalCenter: parent.horizontalCenter
		}
		font.pixelSize: isNxt ? 20 : 16
		font.family: qfont.regular.name
	}
}
