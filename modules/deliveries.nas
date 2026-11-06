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
    { name: "Classified Documents", minWeight: 1, maxWeight: 10, pricePerKg: 35 },
    { name: "Fresh Flowers", minWeight: 5, maxWeight: 25, pricePerKg: 5 },
    { name: "Mail Boxes", minWeight: 15, maxWeight: 30, pricePerKg: 2 },
    { name: "Medical Supplies", minWeight: 10, maxWeight: 60, pricePerKg: 15 },
    { name: "Military Equipment", minWeight: 25, maxWeight: 50, pricePerKg: 25 },
    { name: "Scientific Samples", minWeight: 2, maxWeight: 15, pricePerKg: 20 },
    { name: "Survey Equipment", minWeight: 5, maxWeight: 35, pricePerKg: 5 },
    { name: "Aircraft Spare Parts", minWeight: 5, maxWeight: 55, pricePerKg: 10 },
    { name: "Bakery Products", minWeight: 15, maxWeight: 30, pricePerKg: 2 },
    { name: "Refrigerated Food", minWeight: 10, maxWeight: 40, pricePerKg: 5 },
    { name: "Veterinary Vaccines", minWeight: 1, maxWeight: 10, pricePerKg: 20 },
    { name: "Newspapers and Magazines", minWeight: 30, maxWeight: 60, pricePerKg: 1 },
    { name: "Legal Parcels", minWeight: 1, maxWeight: 15, pricePerKg: 5 },
    { name: "Land Surveying Tripods", minWeight: 5, maxWeight: 30, pricePerKg: 10 },
    { name: "Radio Communication Equipment", minWeight: 5, maxWeight: 30, pricePerKg: 10 },
    { name: "Water Testing Kits", minWeight: 1, maxWeight: 10, pricePerKg: 15 },
    { name: "Computer Components", minWeight: 5, maxWeight: 25, pricePerKg: 15 },
    { name: "Antique Collectibles", minWeight: 2, maxWeight: 25, pricePerKg: 25 },
    { name: "Luxury Goods", minWeight: 3, maxWeight: 20, pricePerKg: 20 },
    { name: "Weather Monitoring Instruments", minWeight: 3, maxWeight: 20, pricePerKg: 15 },
];

var budget = 100;
var searchRangeNm = 500;
var maxOffers = 25;
var offers = [];
var offersAirportId = nil;
var activeJob = nil;
var activeJobIndex = nil;
var deliveryTimer = nil;
var completedDeliveries = 0;
var deliveredCargoKg = 0;
var deliveryDistanceNm = 0;
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
    if (deliveryDistanceNm >= 10000) {
        return "Chief Pilot";
    }
    elsif (deliveryDistanceNm >= 5000) {
        return "Type Rating Instructor";
    }
    elsif (deliveryDistanceNm >= 2500) {
        return "Captain";
    }
    elsif (deliveryDistanceNm >= 500) {
        return "First Officer";
    }
    else {
        return "Cadet";
    }
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

    var nearestAirport = nil;
    var nearestDistance = 999999;

    foreach (var apt; airports) {
        var distance = courseAndDistance(apt)[1];

        if (distance < nearestDistance) {
            nearestDistance = distance;
            nearestAirport = apt;
        }
    }

    if (nearestAirport == nil) {
        return nil;
    }

    return nearestAirport.id;
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

    var destination = activeJob.airportName;
    budget += activeJob.payment;
    completedDeliveries += 1;
    deliveredCargoKg += activeJob.weightKg;
    deliveryDistanceNm += activeJob.distanceNm;
    setprop("/payload/weight[4]/weight-lb", 0);
    setprop("/sim/messages/copilot", "Cargo unloaded successfully!");
    var saved = saveStatistics();

    if (deliveryTimer != nil) {
        deliveryTimer.stop();
    }

    activeJob = nil;
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
    var canAccept = isReadyForDelivery();

        if (activeJob == nil and canAccept) {
            var currentAirportId = getCurrentAirportId();

            if (currentAirportId != nil) {
                if (currentAirportId != offersAirportId) {
                    offers = [];
                    offersAirportId = currentAirportId;
                }

                if (size(offers) == 0) {
                    generateOffers();
                }
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
        if (canAccept) {
            addCell(2, 0, "No nearby airports found.", 300);
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
        addCell(row, 5, offer.distanceNm ~ " NM", widths[5]);

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

        if (activeJob == nil and canAccept) {
            button.setValues({
                binding: {
                    command: "nasal",
                    script: "acs.acceptJob(" ~ i ~ ");"
                }
            });
        }
    }
};

var generateOffers = func {
    if (size(offers) > 0) {
        return offers;
    }

    var airports = findAirportsWithinRange(searchRangeNm);

    foreach (var apt; airports) {
        var distanceNm = courseAndDistance(apt)[1];

        if (distanceNm >= 1 and size(offers) < maxOffers) {
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
                distanceNm: int(distanceNm)
            });
        }
    }
    return offers;
};

var acceptJob = func(index) {
    if (activeJob != nil) {
        return;
    }

    if (!isReadyForDelivery()) {
        return;
    }

    if (index < 0 or index >= size(offers)) {
        return;
    }

    activeJob = offers[index];
    activeJobIndex = index;
    setprop("/payload/weight[4]/weight-lb", activeJob.weightKg * 2.20462262);
    setprop("/sim/messages/copilot", "Cargo loaded successfully!");

    if (deliveryTimer == nil) {
        deliveryTimer = maketimer(10, checkDelivery);
        deliveryTimer.simulatedTime = 10;
    }

    deliveryTimer.start();

    var dialogArgs = props.Node.new({
        "dialog-name": "local-deliveries"
    });

    fgcommand("dialog-close", dialogArgs);
    fgcommand("dialog-show", dialogArgs);
};
