using namespace System.Net

param($Request, $TriggerMetadata)

# Import the OpenAPI generation function
. ".\Modules\CIPPCore\Public\OpenAPI\New-CIPPOpenAPISpec.ps1"

$Resource = $Request.Params.resource
$Headers = @{
    'Content-Type' = 'application/json'
    'Access-Control-Allow-Origin' = '*'
    'Access-Control-Allow-Methods' = 'GET, POST, PUT, DELETE, OPTIONS'
    'Access-Control-Allow-Headers' = 'Content-Type, Authorization'
}

try {
    switch ($Resource) {
        "openapi.json" {
            # Generate and return the OpenAPI specification
            Write-Host "Generating OpenAPI specification..." -ForegroundColor Green
            
            $openApiSpec = New-CIPPOpenAPISpec
            $jsonSpec = $openApiSpec | ConvertTo-Json -Depth 15
            
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Headers = $Headers
                Body = $jsonSpec
            })
        }
        
        "swagger.html" {
            # Return Swagger UI HTML
            # Note: Azure Functions PowerShell runtime sometimes overrides Content-Type
            # We'll force it by setting it in multiple places
            
            $swaggerHtml = @"
<!DOCTYPE html>
<html>
<head>
    <title>CIPP API Documentation</title>
    <meta charset="utf-8">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@4.15.5/swagger-ui.css" />
    <style>
        html {
            box-sizing: border-box;
            overflow: -moz-scrollbars-vertical;
            overflow-y: scroll;
        }
        *, *:before, *:after {
            box-sizing: inherit;
        }
        body {
            margin:0;
            background: #fafafa;
        }
        .swagger-ui .topbar {
            background-color: #1976d2;
        }
        .swagger-ui .info {
            margin: 50px 0;
        }
        .swagger-ui .info .title {
            color: #1976d2;
        }
    </style>
</head>
<body>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist@4.15.5/swagger-ui-bundle.js"></script>
    <script src="https://unpkg.com/swagger-ui-dist@4.15.5/swagger-ui-standalone-preset.js"></script>
    <script>
        window.onload = function() {
            const ui = SwaggerUIBundle({
                url: './openapi.json',
                dom_id: '#swagger-ui',
                deepLinking: true,
                presets: [
                    SwaggerUIBundle.presets.apis,
                    SwaggerUIStandalonePreset
                ],
                plugins: [
                    SwaggerUIBundle.plugins.DownloadUrl
                ],
                layout: "StandaloneLayout",
                defaultModelsExpandDepth: 1,
                defaultModelExpandDepth: 1,
                showExtensions: true,
                showCommonExtensions: true,
                tryItOutEnabled: true
            })
        }
    </script>
</body>
</html>
"@
            
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                ContentType = 'text/html'
                Headers = @{
                    'Cache-Control' = 'no-cache'
                    'Access-Control-Allow-Origin' = '*'
                }
                Body = $swaggerHtml
            })
        }
        
        default {
            # Default to redirect to Swagger UI
            if (-not $Resource) {
                $redirectHtml = @"
<!DOCTYPE html>
<html>
<head>
    <title>CIPP API Documentation</title>
    <meta http-equiv="refresh" content="0; url=./swagger.html">
</head>
<body>
    <h1>CIPP API Documentation</h1>
    <p>Redirecting to <a href="./swagger.html">Swagger UI</a>...</p>
    <p>Or download the <a href="./openapi.json">OpenAPI specification</a> directly.</p>
</body>
</html>
"@
                
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    ContentType = 'text/html'
                    Headers = @{
                        'Access-Control-Allow-Origin' = '*'
                    }
                    Body = $redirectHtml
                })
            }
            else {
                # Resource not found
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Headers = @{
                        'Content-Type' = 'application/json'
                        'Access-Control-Allow-Origin' = '*'
                    }
                    Body = @{ error = "Resource not found. Available resources: openapi.json, swagger.html" } | ConvertTo-Json
                })
            }
        }
    }
}
catch {
    Write-Error "Error serving documentation: $($_.Exception.Message)"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Headers = @{
            'Content-Type' = 'application/json'
            'Access-Control-Allow-Origin' = '*'
        }
        Body = @{ 
            error = "Internal server error while generating documentation"
            details = $_.Exception.Message
        } | ConvertTo-Json
    })
}
