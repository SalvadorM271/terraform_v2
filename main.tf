#add state to s3 bucket
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.33.0"
    }
  }
  required_version = ">= 0.12"
  backend "remote" {
    organization = "personal_demos"

    workspaces {
      name = "week_7_terraform"
    }
  }
  
}

#install aws provider

provider "aws" {
    region = "us-east-2"
}

#creates policy to give write permissions to db

resource "aws_iam_role_policy" "write_policy" {
  name = "lambda_write_policy"
  role = aws_iam_role.writeRole.id

  policy = file("./rols/writeRol/write_policy.json")
}

#creates a policy to give read permissions to db

resource "aws_iam_role_policy" "read_policy" {
  name = "lambda_read_policy"
  role = aws_iam_role.readRole.id

  policy = file("./rols/readRol/read_policy.json")
}

#roles give permissions to lambda to access other services

resource "aws_iam_role" "writeRole" {
  name = "myWriteRole"

  assume_role_policy = file("./rols/writeRol/assume_write_role_policy.json")

}


resource "aws_iam_role" "readRole" {
  name = "myReadRole"

  assume_role_policy = file("./rols/readRol/assume_read_role_policy.json")

}

#compressing the lambdas before uploading them
# zip the code, path.module means current directory
data "archive_file" "zip1" {
 type        = "zip"
 source_file  = "${path.module}/lambdas/read_t.js"
 output_path = "${path.module}/lambdas/read_t.zip"
}

data "archive_file" "zip2" {
 type        = "zip"
 source_file  = "${path.module}/lambdas/write_t.js"
 output_path = "${path.module}/lambdas/write_t.zip"
}

#creates lambdas and attach roles with the needed permission
resource "aws_lambda_function" "writeLambda" {

  function_name = "writeLambda"
  filename = "${path.module}/lambdas/write_t.zip"
  role          = aws_iam_role.writeRole.arn
  handler       = "write_t.handler"
  runtime       = "nodejs16.x"
}


resource "aws_lambda_function" "readLambda" {

  function_name = "readLambda"
  filename = "${path.module}/lambdas/read_t.zip"
  role          = aws_iam_role.readRole.arn
  handler       = "read_t.handler"
  runtime       = "nodejs16.x"
}


# creates a rest api, api gateway
resource "aws_api_gateway_rest_api" "apiLambda" {
  name        = "myAPI"

}

# creates an endpoint for writing to the database
resource "aws_api_gateway_resource" "writeResource" {
  rest_api_id = aws_api_gateway_rest_api.apiLambda.id
  parent_id   = aws_api_gateway_rest_api.apiLambda.root_resource_id
  path_part   = "writedb"

}

# creates an post method for that endpoint, with no api key needed
resource "aws_api_gateway_method" "writeMethod" {
   rest_api_id   = aws_api_gateway_rest_api.apiLambda.id
   resource_id   = aws_api_gateway_resource.writeResource.id
   http_method   = "POST"
   authorization = "NONE"
}

# creates an endpoint for reading the database
resource "aws_api_gateway_resource" "readResource" {
  rest_api_id = aws_api_gateway_rest_api.apiLambda.id
  parent_id   = aws_api_gateway_rest_api.apiLambda.root_resource_id
  path_part   = "readdb"

}

# creates an post method for that endpoint, with no api key needed
resource "aws_api_gateway_method" "readMethod" {
   rest_api_id   = aws_api_gateway_rest_api.apiLambda.id
   resource_id   = aws_api_gateway_resource.readResource.id
   http_method   = "POST"
   authorization = "NONE"
}

# links the lambda function for writing to the database to the post method of the writedb endpoint
resource "aws_api_gateway_integration" "writeInt" {
   rest_api_id = aws_api_gateway_rest_api.apiLambda.id
   resource_id = aws_api_gateway_resource.writeResource.id
   http_method = aws_api_gateway_method.writeMethod.http_method

   integration_http_method = "POST"
   type                    = "AWS_PROXY"
   uri                     = aws_lambda_function.writeLambda.invoke_arn
   
}

# links the lambda function for writing to the database to the post method of the readdb endpoint
resource "aws_api_gateway_integration" "readInt" {
   rest_api_id = aws_api_gateway_rest_api.apiLambda.id
   resource_id = aws_api_gateway_resource.readResource.id
   http_method = aws_api_gateway_method.readMethod.http_method

   integration_http_method = "POST"
   type                    = "AWS_PROXY"
   uri                     = aws_lambda_function.readLambda.invoke_arn

}


# creates an stage for the api
resource "aws_api_gateway_deployment" "apideploy" {
   depends_on = [ aws_api_gateway_integration.writeInt, aws_api_gateway_integration.readInt]

   rest_api_id = aws_api_gateway_rest_api.apiLambda.id
   stage_name  = "Prod"
}

# allows api gateway to call this lambda
resource "aws_lambda_permission" "writePermission" {
   statement_id  = "AllowExecutionFromAPIGateway"
   action        = "lambda:InvokeFunction"
   function_name = aws_lambda_function.writeLambda.function_name
   principal     = "apigateway.amazonaws.com"

   source_arn = "${aws_api_gateway_rest_api.apiLambda.execution_arn}/Prod/POST/writedb"

}

# allows api gateway to call this lambda
resource "aws_lambda_permission" "readPermission" {
   statement_id  = "AllowExecutionFromAPIGateway"
   action        = "lambda:InvokeFunction"
   function_name = aws_lambda_function.readLambda.function_name
   principal     = "apigateway.amazonaws.com"

   source_arn = "${aws_api_gateway_rest_api.apiLambda.execution_arn}/Prod/POST/readdb"

}

# creates table to store data

resource "aws_dynamodb_table" "dbtable" {
  name             = "myTable"
  hash_key         = "id"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  attribute {
    name = "id"
    type = "S"
  }
}

# the link for accessing the api gateway

output "base_url" {
  value = aws_api_gateway_deployment.apideploy.invoke_url
}



/*
resource "aws_api_gateway_method_response" "write_http_status_value" {
  rest_api_id = "${aws_api_gateway_rest_api.apiLambda.id}"
  resource_id = "${aws_api_gateway_resource.writeResource.id}"
  http_method = "${aws_api_gateway_method.writeMethod.http_method}"
  status_code = "200"


  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_method_response" "read_http_status_value" {
  rest_api_id = "${aws_api_gateway_rest_api.apiLambda.id}"
  resource_id = "${aws_api_gateway_resource.readResource.id}"
  http_method = "${aws_api_gateway_method.readMethod.http_method}"
  status_code = "200"


  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "write_integration_response" {
  rest_api_id = "${aws_api_gateway_rest_api.apiLambda.id}"
  resource_id = "${aws_api_gateway_resource.writeResource.id}"
  http_method = "${aws_api_gateway_method.writeMethod.http_method}"
  status_code = "${aws_api_gateway_method_response.write_http_status_value.status_code}"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}

resource "aws_api_gateway_integration_response" "read_integration_response" {
  rest_api_id = "${aws_api_gateway_rest_api.apiLambda.id}"
  resource_id = "${aws_api_gateway_resource.readResource.id}"
  http_method = "${aws_api_gateway_method.readMethod.http_method}"
  status_code = "${aws_api_gateway_method_response.read_http_status_value.status_code}"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}

# add options to both endpoints

# creates an post method for that endpoint, with no api key needed--------------------------------
resource "aws_api_gateway_method" "opt_method" {
   rest_api_id   = aws_api_gateway_rest_api.apiLambda.id
   resource_id   = aws_api_gateway_resource.writeResource.id
   http_method   = "OPTIONS"
   authorization = "NONE"
}

resource "aws_api_gateway_integration" "optInt" {
   rest_api_id = aws_api_gateway_rest_api.apiLambda.id
   resource_id = aws_api_gateway_resource.writeResource.id
   http_method = aws_api_gateway_method.opt_method.http_method

   integration_http_method = "OPTIONS"
   type                    = "AWS_PROXY"
   uri                     = aws_lambda_function.writeLambda.invoke_arn
   
}

resource "aws_api_gateway_method_response" "opt_http_status_value" {
  rest_api_id = "${aws_api_gateway_rest_api.apiLambda.id}"
  resource_id = "${aws_api_gateway_resource.writeResource.id}"
  http_method = "${aws_api_gateway_method.opt_method.http_method}"
  status_code = "200"


  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "opt_integration_response" {
  depends_on = [aws_api_gateway_method_response.opt_http_status_value]
  rest_api_id = "${aws_api_gateway_rest_api.apiLambda.id}"
  resource_id = "${aws_api_gateway_resource.writeResource.id}"
  http_method = "${aws_api_gateway_method.opt_method.http_method}"
  status_code = "${aws_api_gateway_method_response.opt_http_status_value.status_code}"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'POST,GET,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}
*/



