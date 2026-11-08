###########################################################################
#  Air Cargo Simulator                                                    #
#                                                                         #
#  Created by: Georgi Georgiev (RacerBG)                                  #
#                                                                         #
#  Copyright (C) 2026 Georgi Georgiev (RacerBG)                           #
#                                                                         #
#  This program is free software: you can redistribute it and/or modify   #
#  it under the terms of the GNU General Public License as published by   #
#  the Free Software Foundation, either version 3 of the License, or      #
#  (at your option) any later version.                                    #
#                                                                         #
#  This program is distributed in the hope that it will be useful,        #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of         #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the          #
#  GNU General Public License for more details.                           #
###########################################################################

var cargoTypes = [
    { name: "Classified Documents", minWeight: 1, maxWeight: 5, pricePerKg: 40 },
    { name: "Fresh Flowers", minWeight: 10, maxWeight: 30, pricePerKg: 10 },
    { name: "Mail Boxes", minWeight: 25, maxWeight: 50, pricePerKg: 5 },
    { name: "Medical Supplies", minWeight: 15, maxWeight: 60, pricePerKg: 15 },
    { name: "Military Equipment", minWeight: 30, maxWeight: 75, pricePerKg: 15 },
    { name: "Scientific Samples", minWeight: 1, maxWeight: 15, pricePerKg: 20 },
    { name: "Survey Equipment", minWeight: 10, maxWeight: 40, pricePerKg: 5 },
    { name: "Aircraft Spare Parts", minWeight: 15, maxWeight: 65, pricePerKg: 10 },
    { name: "Bakery Products", minWeight: 20, maxWeight: 50, pricePerKg: 2 },
    { name: "Refrigerated Food", minWeight: 15, maxWeight: 50, pricePerKg: 5 },
    { name: "Veterinary Vaccines", minWeight: 1, maxWeight: 15, pricePerKg: 20 },
    { name: "Newspapers and Magazines", minWeight: 50, maxWeight: 100, pricePerKg: 2 },
    { name: "Legal Parcels", minWeight: 1, maxWeight: 5, pricePerKg: 30 },
    { name: "Land Surveying Tripods", minWeight: 10, maxWeight: 40, pricePerKg: 5 },
    { name: "Radio Communication Equipment", minWeight: 10, maxWeight: 40, pricePerKg: 10 },
    { name: "Water Testing Kits", minWeight: 1, maxWeight: 10, pricePerKg: 20 },
    { name: "Computer Components", minWeight: 5, maxWeight: 35, pricePerKg: 15 },
    { name: "Antique Collectibles", minWeight: 2, maxWeight: 30, pricePerKg: 20 },
    { name: "Luxury Goods", minWeight: 5, maxWeight: 25, pricePerKg: 25 },
    { name: "Weather Monitoring Instruments", minWeight: 5, maxWeight: 30, pricePerKg: 15 }
];

var offers = [];
var budget = 100;
var maxOffers = 25;
var searchRangeNm = 500;
var completedDeliveries = 0;
var deliveredCargoKg = 0;
var deliveryDistanceNm = 0;
var activeJob = nil;
var activeJobAircraft = nil;
var activeJobIndex = nil;
var deliveryTimer = nil;
var offersAirportId = nil;
var savePath = getprop("/sim/fg-home") ~ "/Export/ACS-save.xml";

var saveStatistics = func {
    var data = props.Node.new({
        "budget": budget,
        "completed-deliveries": completedDeliveries,
        "delivered-cargo-kg": deliveredCargoKg,
        "delivery-distance-nm": deliveryDistanceNm
    });
    return io.write_properties(savePath, data) != nil;
};

var loadStatistics = func {
    var data = io.read_properties(savePath);

    if (data == nil) {
        return;
    }

    var value = data.getValue("budget");
    if (value != nil) {
        budget = value;
    }

    value = data.getValue("completed-deliveries");
    if (value != nil) {
        completedDeliveries = value;
    }

    value = data.getValue("delivered-cargo-kg");
    if (value != nil) {
        deliveredCargoKg = value;
    }

    value = data.getValue("delivery-distance-nm");
    if (value != nil) {
        deliveryDistanceNm = value;
    }
};

var getReputation = func {
    if (completedDeliveries >= 100 and deliveryDistanceNm >= 10000) {
        return "Chief Pilot";
    }
    elsif (completedDeliveries >= 50 and deliveryDistanceNm >= 5000) {
        return "Type Rating Instructor";
    }
    elsif (completedDeliveries >= 25 and deliveryDistanceNm >= 2500) {
        return "Captain";
    }
    elsif (completedDeliveries >= 5 and deliveryDistanceNm >= 500) {
        return "First Officer";
    }
    else {
        return "Cadet";
    }
};

var getBaggageCompartments = func {
    var payload = props.globals.getNode("/payload");

    if (payload == nil) {
        return [];
    }

    var compartments = [];

    foreach (var weight; payload.getChildren("weight")) {
        var name = weight.getValue("name");
        var maxLb = weight.getValue("max-lb");

        if ((name == "Baggage" or name == "Baggage 1" or name == "Baggage 2" or name == "Luggage") and maxLb != nil and maxLb > 0) {
            append(compartments, {
                index: weight.getIndex(),
                maxLb: maxLb
            });
        }
    }
    return compartments;
};

var getCargoCapacityLb = func(compartments) {
    var capacity = 0;

    foreach (var compartment; compartments) {
        capacity += compartment.maxLb;
    }
    return capacity;
};

var setAircraftCargoWeight = func(compartments, weightLb) {
    var remaining = weightLb;

    foreach (var compartment; compartments) {
        var compartmentWeight = remaining;

        if (compartmentWeight > compartment.maxLb) {
            compartmentWeight = compartment.maxLb;
        }

        setprop("/payload/weight[" ~ compartment.index ~ "]/weight-lb", compartmentWeight);
        remaining -= compartmentWeight;
    }
    return remaining <= 0.001;
};

var isAircraftOnGround = func {
    return getprop("/gear/gear[0]/wow") and getprop("/gear/gear[1]/wow") and getprop("/gear/gear[2]/wow");
};

var isAircraftStopped = func {
    return getprop("/velocities/groundspeed-kt") <= 1;
};

var isAircraftEngineStopped = func {
    return getprop("/engines/engine/running") == 0;
};

var isAircraftLandedAndStopped = func {
    return isAircraftOnGround() and isAircraftStopped() and isAircraftEngineStopped();
};

var isAtAirport = func {
    return size(findAirportsWithinRange(1)) > 0;
};

var getCurrentAirportId = func {
    var airports = findAirportsWithinRange(1);

    if (size(airports) == 0) {
        return nil;
    }
    return airports[0].id;
};

var isReadyForDelivery = func {
    return isAircraftLandedAndStopped() and isAtAirport();
};

var isAtDeliveryDestination = func {
    if (activeJob == nil) {
        return false;
    }

    var nearbyAirports = findAirportsWithinRange(1);

    foreach (var apt; nearbyAirports) {
        if (apt.id == activeJob.airportId) {
            return true;
        }
    }
    return false;
};

var checkDelivery = func {
    if (activeJob == nil) {
        deliveryTimer.stop();
        return;
    }

    if (isAircraftLandedAndStopped() and isAtDeliveryDestination()) {
        completeDelivery();
        return;
    }

    deliveryTimer.restart(10);
};

var completeDelivery = func {
    if (activeJob == nil) {
        return;
    }

    budget += activeJob.payment;
    completedDeliveries += 1;
    deliveredCargoKg += activeJob.weightKg;
    deliveryDistanceNm += activeJob.distanceNm;
    setAircraftCargoWeight(activeJobAircraft, 0);
    setprop("/sim/messages/copilot", "Cargo unloaded successfully!");

    if (deliveryTimer != nil) {
        deliveryTimer.stop();
    }

    activeJob = nil;
    activeJobAircraft = nil;
    activeJobIndex = nil;
    offers = [];
    offersAirportId = getCurrentAirportId();
    generateOffers();
};

var populateMessage = func(dialog) {
    var destinationLabel = dialog.getNode("group[1]/text[0]/label");
    var cargoLabel = dialog.getNode("group[1]/text[1]/label");
    var weightLabel = dialog.getNode("group[1]/text[2]/label");
    var paymentLabel = dialog.getNode("group[1]/text[3]/label");
    var distanceLabel = dialog.getNode("group[1]/text[4]/label");

    if (destinationLabel == nil or cargoLabel == nil or
        weightLabel == nil or paymentLabel == nil or
        distanceLabel == nil) {
        return;
    }

    if (activeJob == nil) {
        destinationLabel.setValue("No delivery has been selected yet.");
        cargoLabel.setValue("");
        weightLabel.setValue("Available cargo offers can be found at the airports.");
        paymentLabel.setValue("");
        distanceLabel.setValue("Complete deliveries to earn money and increase your rank.");
    } else {
        destinationLabel.setValue("Destination Airport: " ~ activeJob.airportName ~ " (" ~ activeJob.airportId ~ ")");
        cargoLabel.setValue("Cargo Type: " ~ activeJob.cargoName);
        weightLabel.setValue("Weight: " ~ activeJob.weightKg ~ " KG");
        paymentLabel.setValue("Earnings: " ~ activeJob.payment ~ " EUR");
        distanceLabel.setValue("Delivery Distance: " ~ sprintf("%.1f", activeJob.distanceNm) ~ " NM");
    }
};

var populateStatistics = func(dialog) {
    var budgetLabel = dialog.getNode("group[1]/text[0]/label");
    var deliveriesLabel = dialog.getNode("group[1]/text[1]/label");
    var cargoLabel = dialog.getNode("group[1]/text[2]/label");
    var distanceLabel = dialog.getNode("group[1]/text[3]/label");
    var reputationLabel = dialog.getNode("group[1]/text[4]/label");

    if (budgetLabel != nil) {
        budgetLabel.setValue("Budget: " ~ budget ~ " EUR");
    }

    if (deliveriesLabel != nil) {
        deliveriesLabel.setValue("Completed Deliveries: " ~ completedDeliveries);
    }

    if (cargoLabel != nil) {
        cargoLabel.setValue("Delivered Cargo: " ~ deliveredCargoKg ~ " KG");
    }

    if (distanceLabel != nil) {
        distanceLabel.setValue("Covered Distance: " ~ sprintf("%.1f", deliveryDistanceNm) ~ " NM");
    }

    if (reputationLabel != nil) {
        reputationLabel.setValue("Rank: " ~ getReputation());
    }
};

var populateDialog = func(dialog) {
    var onGround = isAircraftOnGround();
    var canAccept = false;
    var canSearchOffers = false;
    var currentAirportId = nil;

    if (onGround) {
        canAccept = isAircraftStopped() and isAircraftEngineStopped();
        currentAirportId = getCurrentAirportId();
        canSearchOffers = currentAirportId != nil;
        canAccept = canAccept and canSearchOffers;
    }

    if (activeJob == nil and canSearchOffers) {
        if (currentAirportId != offersAirportId) {
            offers = [];
            offersAirportId = currentAirportId;
        }

        if (size(offers) == 0) {
            generateOffers();
        }
    }

    var list = dialog.getNode("group[1]/group[0]");

    if (list == nil) {
        return;
    }

    list.removeChildren();

    list.setValues({
        layout: "table",
        "default-padding": 4
        });

    var addCell = func(row, col, label, width) {
        var cell = list.addChild("text");

        cell.setValues({
            label: label,
            row: row,
            col: col,
            "pref-width": width,
            halign: "left"
        });
    };

    var headings = [
        "ICAO",
        "Airport Name",
        "Cargo Type",
        "Weight",
        "Earnings",
        "Distance",
        "Action"
    ];

    var widths = [50, 300, 200, 75, 75, 75, 75];

    for (var col = 0; col < size(headings); col += 1) {
        var cell = list.addChild("text");

        cell.setValues({
            label: headings[col],
            row: 0,
            col: col,
            "pref-width": widths[col]
        });
    }

    if (size(offers) == 0) {
        for (var row = 2; row < maxOffers + 2; row += 1) {
            for (var col = 0; col < size(widths); col += 1) {
                addCell(row, col, "", widths[col]);
            }
        }
        return;
    }

    for (var i = 0; i < size(offers); i += 1) {
        var offer = offers[i];
        var row = i + 2;

        addCell(row, 0, offer.airportId, widths[0]);
        addCell(row, 1, offer.airportName, widths[1]);
        addCell(row, 2, offer.cargoName, widths[2]);
        addCell(row, 3, offer.weightKg ~ " KG", widths[3]);
        addCell(row, 4, offer.payment ~ " EUR", widths[4]);
        addCell(row, 5, sprintf("%.1f", offer.distanceNm) ~ " NM", widths[5]);

        var buttonText = "N/A";

        if (activeJobIndex == i) {
            buttonText = "ACTIVE";
        } elsif (activeJob == nil and canAccept) {
            buttonText = "SELECT";
        }

        var button = list.addChild("button");

        button.setValues({
            legend: buttonText,
            row: row,
            col: 6,
            "pref-width": 64,
            "pref-height": 16
        });

        if (buttonText == "SELECT") {
            button.setValues({
                binding: {
                    command: "nasal",
                    script: "acs.acceptJob(" ~ i ~ ");"
                }
            });
        } else {
            var enableCondition = button.addChild("enable");
            enableCondition.addChild("false");
        }
    }
};

var generateOffers = func {
    if (size(offers) > 0) {
        return offers;
    }

    var airports = findAirportsWithinRange(searchRangeNm);

    foreach (var apt; airports) {
        if (size(offers) >= maxOffers) {
            return offers;
        }

        var distanceNm = courseAndDistance(apt)[1];

        if (distanceNm >= 1) {
            var cargo = cargoTypes[
                math.floor(rand() * size(cargoTypes))
            ];

            var weight = cargo.minWeight + math.floor(rand() * (cargo.maxWeight - cargo.minWeight + 1));

            append(offers, {
                airportId: apt.id,
                airportName: apt.name,
                cargoName: cargo.name,
                weightKg: int(weight),
                payment: int(weight * cargo.pricePerKg),
                distanceNm: distanceNm
            });
        }
    }
    return offers;
};

var acceptJob = func(index) {
    if (activeJob != nil) {
        return;
    }

    if (index < 0 or index >= size(offers)) {
        return;
    }

    var compartments = getBaggageCompartments();

    if (size(compartments) == 0) {
        setprop("/sim/messages/copilot", "Aircraft not supported!");
        return;
    }

    if (!isReadyForDelivery()) {
        return;
    }

    var cargoWeightLb = offers[index].weightKg * 2.20462262;

    if (cargoWeightLb > getCargoCapacityLb(compartments)) {
        setprop("/sim/messages/copilot", "Cargo too heavy!");
        return;
    }

    activeJob = offers[index];
    activeJobAircraft = compartments;
    activeJobIndex = index;
    setAircraftCargoWeight(compartments, cargoWeightLb);
    setprop("/sim/messages/copilot", "Cargo loaded successfully!");

    if (deliveryTimer == nil) {
        deliveryTimer = maketimer(10, checkDelivery);
        deliveryTimer.simulatedTime = 1;
    }

    deliveryTimer.start();

    var dialogArgs = props.Node.new({
        "dialog-name": "local-deliveries"
    });

    fgcommand("dialog-close", dialogArgs);
    fgcommand("dialog-show", dialogArgs);
};
