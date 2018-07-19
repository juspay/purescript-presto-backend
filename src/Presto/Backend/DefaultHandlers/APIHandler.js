/*
* Copyright (c) 2012-2017 "JUSPAY Technologies"
* JUSPAY Technologies Pvt. Ltd. [https://www.juspay.in]
*
* This file is part of JUSPAY Platform.
*
* JUSPAY Platform is free software: you can redistribute it and/or modify
* it for only educational purposes under the terms of the GNU Affero General
* Public License (GNU AGPL) as published by the Free Software Foundation,
* either version 3 of the License, or (at your option) any later version.
* For Enterprise/Commerical licenses, contact <info@juspay.in>.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  The end user will
* be liable for all damages without limitation, which is caused by the
* ABUSE of the LICENSED SOFTWARE and shall INDEMNIFY JUSPAY for such
* damages, claims, cost, including reasonable attorney fee claimed on Juspay.
* The end user has NO right to claim any indemnification based on its use
* of Licensed Software. See the GNU Affero General Public License for more details.
*
* You should have received a copy of the GNU Affero General Public License
* along with this program. If not, see <https://www.gnu.org/licenses/agpl.html>.
*/

var axios = require("axios");


var callAPIFn = function(error) {
  return function(success) {
    return function(request) {
      return function() {
        var headersRaw = request.headers;
        var headers = {};
        for(var i=0;i<headersRaw.length;i++){
          headers[headersRaw[i].field] = headersRaw[i].value;
        }
        return axios.request({
          url: request.url,
          method: request.method,
          data: request.payload,
          headers: headers
        })
        .then(function(response) {
          success(JSON.stringify({
            code:response.status,
            status:response.statusText,
            response:response.data
          }))();
        })
        .catch(function(err) {
          var response  = err.response;
          if(checkForNullOrUndefined(response.status) && checkForNullOrUndefined(response.statusText) && checkForNullOrUndefined(response.data)) {
            // if(response.status === 200 || response.status === "200") {
              success(JSON.stringify({
                code:response.status,
                status:response.statusText,
                response:response.data
              }))();
            // } else {
            //   error(JSON.stringify({
            //     code:response.status,
            //     status:response.statusText,
            //     response:response.data
            //   }))();
            // }
          } else {
            error("Not able to find code/status/data in response")();
          }
        });
      }
    };
  };
};

var checkForNullOrUndefined = function(value) {
  if(value !== null && value !== undefined) {
    return true;
  }
  else { 
    return false;
  }
}

exports["callAPI'"] = callAPIFn;

exports["logString'"] = function(data) {
  console.log("logString " + JSON.stringify(data));
}


exports["callAPI'"] = callAPIFn;

exports["logString'"] = function(data) {
  console.log("logString " + JSON.stringify(data));
}
