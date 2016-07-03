//
//  WMATAFetcher.swift
//  DCMetro
//
//  Created by Christopher Rung on 6/30/16.
//  Copyright © 2016 Christopher Rung. All rights reserved.
//

import Foundation
import SwiftyJSON
import CoreLocation

var predictionJSON: JSON = JSON.null
var trains: [Train] = []

func getPrediction(stationCode: String, onCompleted: (result: JSON?) -> ()) {
	guard let wmataURL = NSURL(string: "https://api.wmata.com/StationPrediction.svc/json/GetPrediction/" + stationCode) else {
		debugPrint("Error: cannot create URL")
		return
	}
	
	let request = NSMutableURLRequest(URL: wmataURL)
	let session = NSURLSession.sharedSession()
	
	request.setValue("[WMATA_KEY_GOES_HERE]", forHTTPHeaderField:"api_key")
	
	session.dataTaskWithRequest(request, completionHandler: { (data: NSData?, response: NSURLResponse?, error: NSError?) in
		if error == nil {
			onCompleted(result: JSON(data: data!))
		} else {
			debugPrint(error)
		}
	}).resume()
}

func populateTrainArray() {
	// the JSON only contains one root element, "Trains"
	predictionJSON = predictionJSON["Trains"]
	
	for (_, subJson): (String, JSON) in predictionJSON {
		var line: Line? = nil
		var min: String? = nil
		var numCars: String? = nil
		var destination: Station? = nil
		
		if subJson["DestinationName"].stringValue == Station.No.description || subJson["DestinationName"].stringValue == Station.Train.description {
			line = Line.NO
			min = subJson["Min"] == nil ? "-" : subJson["Min"].stringValue
			numCars = "-"
			destination = subJson["DestinationName"].stringValue == Station.No.description ? Station.No : Station.Train
		}
		
		if subJson["Min"].stringValue == "" {
			continue
		}
		
		trains.append(Train(numCars: numCars ?? subJson["Car"].stringValue,
			destination: destination ?? Station(rawValue: subJson["DestinationCode"].stringValue)!,
			group: subJson["Group"].stringValue,
			line: line ?? Line(rawValue: subJson["Line"].stringValue)!,
			location: Station(rawValue: subJson["LocationCode"].stringValue)!,
			min: min ?? subJson["Min"].stringValue))
	}
	
	trains.sortInPlace { (train1: Train, train2: Train) -> Bool in
		if train1.min == "BRD" || train1.min == "ARR" {
			return true
		} else if train2.min == "BRD" || train2.min == "ARR" {
			return false
		}
		return train1.min < train2.min
	}
	trains.sortInPlace({ $0.destination.description.compare($1.destination.description) == .OrderedAscending })
	trains.sortInPlace({ $0.group < $1.group })
}

func setSelectedStationLabelAndGetPredictions() {
	timeBefore = NSDate()
	getPrediction(selectedStation.rawValue, onCompleted: {
		result in
		predictionJSON = result!
		trains = []
		populateTrainArray()
		handleTwoLevelStation()
		NSNotificationCenter.defaultCenter().postNotificationName("reloadTable", object: nil)
	})
}

/**
Checks the selected station to see if it is one of the four metro stations that have two levels.  If it is, fetch the predictions for the second station code, add it to the trains array, and reload the table view.

WMATA API: "Some stations have two platforms (e.g.: Gallery Place, Fort Totten, L'Enfant Plaza, and Metro Center). To retrieve complete predictions for these stations, be sure to pass in both StationCodes.
*/
func handleTwoLevelStation() {
	let twoLevelStations = [Station.B01, Station.B06, Station.D03, Station.A01]
	
	if twoLevelStations.contains(selectedStation) {
		let trainsGroup1 = trains
		
		switch selectedStation {
		case Station.A01: selectedStation = Station.C01
		case Station.B01: selectedStation = Station.F01
		case Station.B06: selectedStation = Station.E06
		case Station.D03: selectedStation = Station.F03
		default: break
		}
		
		getPrediction(selectedStation.rawValue, onCompleted: {
			result in
			predictionJSON = result!
			trains = []
			populateTrainArray()
			trains = trains + trainsGroup1
		})
	}
}

func getSixClosestStations(location: CLLocation) -> [Station] {
	var sixClosestStations = [Station]()
	var distancesDictionary: [CLLocationDistance:String] = [:]
	
	for station in Station.allValues {
		distancesDictionary[station.location.distanceFromLocation(location)] = station.rawValue
	}
	
	let sortedDistancesKeys = Array(distancesDictionary.keys).sort(<)
	
	for (index, key) in sortedDistancesKeys.enumerate() {
		sixClosestStations.append(Station(rawValue: distancesDictionary[key]!)!)
		if index == 5 {
			break;
		}
	}
	
	return sixClosestStations
}