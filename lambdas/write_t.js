var AWS = require('aws-sdk');
var ddb = new AWS.DynamoDB({apiVersion: '2012-08-10'});

exports.handler = async (event) => {
    try {
	    var obj = JSON.parse(event.body);
	    var ID = obj.id;
	    var NAME = obj.name;
		var PRICE = obj.price;
	    var params = {
		    TableName:'myTable',
		    Item: {
			    id : {S: ID},
			    name : {S: NAME},
				price: {S: PRICE}
		    }
	    };
	    var data;
	    var msg;
	    try{
		    data = await ddb.putItem(params).promise();
		    console.log("Item entered successfully:", data);
		    msg = 'Item entered successfully';
	    } catch(err){
		    console.log("Error: ", err);
		    msg = err;
	    }
	    var response = {
		    'statusCode': 200,
			headers: {
				"Access-Control-Allow-Headers" : "Content-Type",
				"Access-Control-Allow-Origin": "*",
				"Access-Control-Allow-Methods": "OPTIONS,POST,GET"
			},
		    'body': JSON.stringify({
			    message: msg
		    })
	    };
    } catch (err) {
	    console.log(err);
	    return err;
    }
	
    return response;
};