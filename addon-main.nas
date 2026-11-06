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

var main = func(addon) {
    io.load_nasal(addon.basePath ~ "/modules/deliveries.nas", "acs");
    acs.loadStatistics();
};
