function Parse-StructuredNotes {
    param(
        [string]$NotesContent,
        [string]$FunctionName
    )
    
    $operation = New-DefaultOpenAPIOperation -FunctionName $FunctionName
    
    # Example: Parse Summary, Description, Tags from notes
    $summaryMatch = [regex]::Match($NotesContent, 'Summary:\s*(.+)')
    if ($summaryMatch.Success) {
        $operation.summary = $summaryMatch.Groups[1].Value.Trim()
    }
    
    $descMatch = [regex]::Match($NotesContent, 'Description:\s*(.+)')
    if ($descMatch.Success) {
        $operation.description = $descMatch.Groups[1].Value.Trim()
    }
    
    $tagsMatch = [regex]::Match($NotesContent, 'Tags:\s*(.+)')
    if ($tagsMatch.Success) {
        $operation.tags = $tagsMatch.Groups[1].Value.Split(',').Trim()
    }
    
    # Parse Group for organizing endpoints
    $groupMatch = [regex]::Match($NotesContent, 'Group:\s*(.+)')
    if ($groupMatch.Success) {
        $groupName = $groupMatch.Groups[1].Value.Trim()
        # Add group as primary tag
        $operation.tags = @($groupName) + $operation.tags
    }
    
    # Example: Parse Parameters
    $paramMatches = [regex]::Matches($NotesContent, 'Parameter:\s*(.+)')
    if ($paramMatches.Count -gt 0) {
        $operation.parameters = @()
        foreach ($match in $paramMatches) {
            $paramString = $match.Groups[1].Value.Trim()
            
            # Example format: "name (type) [in] - description"
            $paramPattern = '(\w+)\s+\((\w+)\)\s+\[(\w+)\]\s*-\s*(.+)'
            $paramDetailMatch = [regex]::Match($paramString, $paramPattern)
            
            if ($paramDetailMatch.Success) {
                $operation.parameters += @{
                    name = $paramDetailMatch.Groups[1].Value
                    schema = @{
                        type = $paramDetailMatch.Groups[2].Value
                    }
                    in = $paramDetailMatch.Groups[3].Value
                    description = $paramDetailMatch.Groups[4].Value
                    required = $false
                }
            }
        }
    }
    
    # Parse Response documentation
    $responseMatches = [regex]::Matches($NotesContent, 'Response:\s*(.+)')
    if ($responseMatches.Count -gt 0) {
        $responseDescription = @()
        foreach ($match in $responseMatches) {
            $responseDescription += $match.Groups[1].Value.Trim()
        }
        
        # Parse Example if provided
        $exampleMatch = [regex]::Match($NotesContent, 'Example:\s*(.+?)(?=\s*\w+:|\s*$)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $exampleValue = $null
        if ($exampleMatch.Success) {
            try {
                $exampleText = $exampleMatch.Groups[1].Value.Trim()
                # Try to parse as JSON
                $exampleValue = $exampleText | ConvertFrom-Json
            }
            catch {
                # If not valid JSON, treat as string
                $exampleValue = $exampleMatch.Groups[1].Value.Trim()
            }
        }
        
        # Create enhanced response with detailed description and examples
        $responseContent = @{
            "application/json" = @{
                schema = @{
                    type = "array"
                    items = @{
                        type = "object"
                        description = "User object with comprehensive details"
                    }
                }
            }
        }
        
        # Add example if provided
        if ($exampleValue) {
            $responseContent["application/json"].examples = @{
                "default" = @{
                    summary = "Example response"
                    value = $exampleValue
                }
            }
        }
        
        $operation.responses = @{
            "200" = @{
                description = "Successful operation. " + ($responseDescription -join " ")
                content = $responseContent
            }
            "400" = @{
                description = "Bad request - Invalid parameters"
                content = @{
                    "application/json" = @{
                        schema = @{
                            '$ref' = "#/components/schemas/ErrorResponse"
                        }
                    }
                }
            }
            "401" = @{
                description = "Unauthorized - Invalid or missing authentication"
            }
            "500" = @{
                description = "Internal server error"
            }
        }
    }
    
    return $operation
}

function New-CIPPOpenAPISpec {
    <#
    .SYNOPSIS
    Generates OpenAPI specification from CIPP PowerShell functions with decorators
    
    .DESCRIPTION
    Scans CIPP HTTP functions for OpenAPI decorators in comments and generates a complete OpenAPI 3.0 specification
    
    .PARAMETER OutputPath
    Path where to save the generated OpenAPI JSON file
    
    .PARAMETER IncludeSwaggerUI
    Whether to also generate a Swagger UI HTML file
    
    .EXAMPLE
    New-CIPPOpenAPISpec -OutputPath "openapi.json" -IncludeSwaggerUI
    #>
    
    param(
        [string]$OutputPath = "openapi.json",
        [switch]$IncludeSwaggerUI
    )
    
    # Base OpenAPI structure
    $openApiSpec = @{
        openapi = "3.0.0"
        info = @{
            title = "CIPP API"
            description = "API for Cyberdrain Improved Partner Portal (CIPP)"
            version = "1.0.0"
            contact = @{
                name = "CIPP Team"
                url = "https://cipp.app"
            }
            license = @{
                name = "AGPL-3.0"
                url = "https://github.com/KelvinTegelaar/CIPP-API/blob/main/LICENSE"
            }
        }
        servers = @(
            @{
                url = "/api"
                description = "CIPP API Server"
            }
        )
        components = @{
            schemas = @{
                StandardResponse = @{
                    type = "object"
                    properties = @{
                        Results = @{
                            type = "object"
                            description = "The results of the operation"
                        }
                        Metadata = @{
                            type = "object"
                            description = "Additional metadata about the operation"
                        }
                    }
                }
                ErrorResponse = @{
                    type = "object"
                    properties = @{
                        error = @{
                            type = "string"
                            description = "Error message"
                        }
                        details = @{
                            type = "string"
                            description = "Detailed error information"
                        }
                    }
                }
            }
            securitySchemes = @{
                BearerAuth = @{
                    type = "http"
                    scheme = "bearer"
                    bearerFormat = "JWT"
                }
            }
        }
        security = @(
            @{
                BearerAuth = @()
            }
        )
        paths = @{}
    }
    
    # Find all Invoke-* HTTP functions
    $httpFunctionsPath = "Modules/CIPPCore/Public/Entrypoints/HTTP Functions"
    if (Test-Path $httpFunctionsPath) {
        $functionFiles = Get-ChildItem -Path $httpFunctionsPath -Recurse -Filter "Invoke-*.ps1"
        
        foreach ($file in $functionFiles) {
            Write-Host "Processing function: $($file.Name)" -ForegroundColor Green
            
            try {
                # Read the function file
                $content = Get-Content -Path $file.FullName -Raw
                
                # Extract function name (remove "Invoke-" prefix)
                $functionName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                $endpointName = $functionName -replace "^Invoke-", ""
                
                # Parse the function for OpenAPI metadata
                $apiMetadata = Parse-FunctionForOpenAPI -Content $content -FunctionName $functionName
                
                if ($apiMetadata) {
                    # Determine HTTP method based on function name patterns
                    $httpMethod = Get-HttpMethodFromFunctionName -FunctionName $functionName
                    
                    # Build the path
                    $path = "/$endpointName"
                    
                    # Initialize path if not exists
                    if (-not $openApiSpec.paths[$path]) {
                        $openApiSpec.paths[$path] = @{}
                    }
                    
                    # Add the operation
                    $openApiSpec.paths[$path][$httpMethod] = $apiMetadata
                }
            }
            catch {
                Write-Warning "Failed to process $($file.Name): $($_.Exception.Message)"
            }
        }
    }
    
    # Convert to JSON and save
    $jsonSpec = $openApiSpec | ConvertTo-Json -Depth 10
    $jsonSpec | Out-File -FilePath $OutputPath -Encoding UTF8
    
    Write-Host "OpenAPI specification generated: $OutputPath" -ForegroundColor Green
    
    # Generate Swagger UI if requested
    if ($IncludeSwaggerUI) {
        New-SwaggerUI -OpenAPISpecPath $OutputPath
    }
    
    return $openApiSpec
}

function Parse-FunctionForOpenAPI {
    param(
        [string]$Content,
        [string]$FunctionName
    )
    
    # Extract OpenAPI JSON block from .NOTES section
    $notesPattern = '(?s)\.NOTES\s*\s*(.+?)(?=\s*\.|\s*#>)'
    $match = [regex]::Match($Content, $notesPattern)
    
    if (-not $match.Success) {
        # No .NOTES found, create default
        return New-DefaultOpenAPIOperation -FunctionName $FunctionName -Content $Content
    }
    
    $notesContent = $match.Groups[1].Value.Trim()
    
    # Check if .NOTES contains JSON (starts with { and ends with })
    if ($notesContent -match '^\s*\{.*\}\s*$') {
        # Parse as JSON OpenAPI spec
        try {
            $openApiSpec = $notesContent | ConvertFrom-Json
            
            # Convert PowerShell object to hashtable for proper JSON serialization
            return ConvertTo-HashtableRecursive -InputObject $openApiSpec
        }
        catch {
            Write-Warning "Failed to parse OpenAPI JSON in .NOTES for $FunctionName`: $($_.Exception.Message)"
        }
    }
    
    # If not JSON or parsing failed, treat as structured text
    $parsedSpec = Parse-StructuredNotes -NotesContent $notesContent -FunctionName $FunctionName
    if ($parsedSpec) {
        return $parsedSpec
    }
    
    # Fall back to default
    return New-DefaultOpenAPIOperation -FunctionName $FunctionName -Content $Content
}

function ConvertTo-HashtableRecursive {
    param([Parameter(ValueFromPipeline)]$InputObject)
    
    if ($InputObject -is [PSCustomObject]) {
        $hashtable = @{}
        $InputObject.PSObject.Properties | ForEach-Object {
            $hashtable[$_.Name] = ConvertTo-HashtableRecursive $_.Value
        }
        return $hashtable
    }
    elseif ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        return @($InputObject | ForEach-Object { ConvertTo-HashtableRecursive $_ })
    }
    else {
        return $InputObject
    }
}

function New-DefaultOpenAPIOperation {
    param(
        [string]$FunctionName,
        [string]$Content
    )
    
    # Extract existing .SYNOPSIS and .DESCRIPTION if available
    $synopsis = ""
    $description = ""
    
    $synopsisMatch = [regex]::Match($Content, '\.SYNOPSIS\s*\s*(.+?)(?=\s*\.|\s*#>)')
    if ($synopsisMatch.Success) {
        $synopsis = $synopsisMatch.Groups[1].Value.Trim()
    }
    
    $descMatch = [regex]::Match($Content, '\.DESCRIPTION\s*\s*(.+?)(?=\s*\.|\s*#>)')
    if ($descMatch.Success) {
        $description = $descMatch.Groups[1].Value.Trim()
    }
    
    # Determine category/tag from file path
    $category = Get-CategoryFromFunctionName -FunctionName $FunctionName
    
    # Extract parameters from the content
    $parameters = Get-ParametersFromContent -Content $Content
    
    $cleanFunctionName = $FunctionName -replace '^Invoke-', ''
    $operation = @{
        summary = if ($synopsis) { $synopsis } else { $cleanFunctionName }
        description = if ($description) { $description } else { "Executes $cleanFunctionName operation" }
        tags = @($category)
        parameters = $parameters
        responses = @{
            "200" = @{
                description = "Successful operation"
                content = @{
                    "application/json" = @{
                        schema = @{
                            '$ref' = "#/components/schemas/StandardResponse"
                        }
                    }
                }
            }
            "400" = @{
                description = "Bad request"
                content = @{
                    "application/json" = @{
                        schema = @{
                            '$ref' = "#/components/schemas/ErrorResponse"
                        }
                    }
                }
            }
            "401" = @{
                description = "Unauthorized"
            }
            "500" = @{
                description = "Internal server error"
            }
        }
    }
    
    return $operation
}

function Get-HttpMethodFromFunctionName {
    param([string]$FunctionName)
    
    if ($FunctionName -match "^Invoke-List|^Invoke-Get") {
        return "get"
    }
    elseif ($FunctionName -match "^Invoke-Add|^Invoke-New|^Invoke-Create") {
        return "post"
    }
    elseif ($FunctionName -match "^Invoke-Edit|^Invoke-Set|^Invoke-Update") {
        return "put"
    }
    elseif ($FunctionName -match "^Invoke-Remove|^Invoke-Delete") {
        return "delete"
    }
    elseif ($FunctionName -match "^Invoke-Exec") {
        return "post"  # Most exec functions are POST operations
    }
    else {
        return "get"  # Default to GET
    }
}

function Get-CategoryFromFunctionName {
    param([string]$FunctionName)
    
    # Extract category from function name patterns
    if ($FunctionName -match "User") { return "Users" }
    elseif ($FunctionName -match "Group") { return "Groups" }
    elseif ($FunctionName -match "Tenant") { return "Tenants" }
    elseif ($FunctionName -match "App|Application") { return "Applications" }
    elseif ($FunctionName -match "Device") { return "Devices" }
    elseif ($FunctionName -match "Mail|Exchange") { return "Exchange" }
    elseif ($FunctionName -match "Teams|Sharepoint") { return "Teams & SharePoint" }
    elseif ($FunctionName -match "Security") { return "Security" }
    elseif ($FunctionName -match "License") { return "Licenses" }
    elseif ($FunctionName -match "Conditional") { return "Conditional Access" }
    elseif ($FunctionName -match "GDAP") { return "GDAP" }
    elseif ($FunctionName -match "Standard") { return "Standards" }
    elseif ($FunctionName -match "Scheduled|Schedule") { return "Scheduler" }
    elseif ($FunctionName -match "Extension") { return "Extensions" }
    else { return "General" }
}

function Get-ParametersFromContent {
    param([string]$Content)
    
    $parameters = @()
    
    # Look for common CIPP parameters in the content
    if ($Content -match '\$Request\.Query\.tenantFilter|\$TenantFilter') {
        $parameters += @{
            name = "TenantFilter"
            in = "query"
            description = "The tenant to filter on"
            required = $false
            schema = @{
                type = "string"
            }
        }
    }
    
    if ($Content -match '\$Request\.Query\.UserID|\$userid') {
        $parameters += @{
            name = "UserID"
            in = "query"
            description = "The user ID to operate on"
            required = $false
            schema = @{
                type = "string"
            }
        }
    }
    
    if ($Content -match '\$Request\.Query\.ID|\$Request\.Query\.id') {
        $parameters += @{
            name = "ID"
            in = "query"
            description = "The ID of the resource"
            required = $false
            schema = @{
                type = "string"
            }
        }
    }
    
    if ($Content -match '\$Request\.Query\.GraphFilter|\$GraphFilter') {
        $parameters += @{
            name = "GraphFilter"
            in = "query"
            description = "Graph API filter to apply"
            required = $false
            schema = @{
                type = "string"
            }
        }
    }
    
    return $parameters
}

function New-SwaggerUI {
    param([string]$OpenAPISpecPath)
    
    $swaggerHtml = @"
<!DOCTYPE html>
<html>
<head>
    <title>CIPP API Documentation</title>
    <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@3.52.5/swagger-ui.css" />
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
    </style>
</head>
<body>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist@3.52.5/swagger-ui-bundle.js"></script>
    <script src="https://unpkg.com/swagger-ui-dist@3.52.5/swagger-ui-standalone-preset.js"></script>
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
                layout: "StandaloneLayout"
            })
        }
    </script>
</body>
</html>
"@
    
    $swaggerPath = [System.IO.Path]::ChangeExtension($OpenAPISpecPath, "html")
    $swaggerHtml | Out-File -FilePath $swaggerPath -Encoding UTF8
    
    Write-Host "Swagger UI generated: $swaggerPath" -ForegroundColor Green
}

# Export-ModuleMember -Function New-CIPPOpenAPISpec
