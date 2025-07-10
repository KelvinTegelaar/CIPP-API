# Generate OpenAPI Specification for CIPP
# This script generates the OpenAPI specification from decorated PowerShell functions

param(
    [string]$OutputPath = "openapi.json",
    [switch]$IncludeSwaggerUI,
    [switch]$TestMode
)

# Import the OpenAPI generation functions
try {
    . ".\Modules\CIPPCore\Public\OpenAPI\New-CIPPOpenAPISpec.ps1"
    Write-Host "Loaded OpenAPI generation functions" -ForegroundColor Green
}
catch {
    Write-Error "Failed to load OpenAPI generation functions: $($_.Exception.Message)"
    exit 1
}

Write-Host "Generating CIPP OpenAPI Specification..." -ForegroundColor Cyan
Write-Host "Output path: $OutputPath" -ForegroundColor Yellow

try {
    # Generate the specification
    $openApiSpec = New-CIPPOpenAPISpec -OutputPath $OutputPath -IncludeSwaggerUI:$IncludeSwaggerUI
    
    Write-Host "OpenAPI specification generated successfully!" -ForegroundColor Green
    Write-Host "File: $OutputPath" -ForegroundColor White
    
    if ($IncludeSwaggerUI) {
        $swaggerPath = [System.IO.Path]::ChangeExtension($OutputPath, "html")
        Write-Host "Swagger UI: $swaggerPath" -ForegroundColor White
    }
    
    # Show some statistics
    $pathCount = $openApiSpec.paths.Count
    $totalOperations = 0
    $openApiSpec.paths.Values | ForEach-Object {
        $totalOperations += $_.Count
    }
    
    Write-Host "Statistics:" -ForegroundColor Cyan
    Write-Host "   Total endpoints: $pathCount" -ForegroundColor White
    Write-Host "   Total operations: $totalOperations" -ForegroundColor White
    
    # Show a few example endpoints
    Write-Host "Example endpoints:" -ForegroundColor Cyan
    $openApiSpec.paths.Keys | Select-Object -First 5 | ForEach-Object {
        $methods = $openApiSpec.paths[$_].Keys -join ", "
        Write-Host "   $_ [$methods]" -ForegroundColor White
    }
    
    if ($TestMode) {
        Write-Host "Test mode: Displaying first endpoint details..." -ForegroundColor Magenta
        $firstPath = $openApiSpec.paths.Keys | Select-Object -First 1
        $firstOperation = $openApiSpec.paths[$firstPath].Values | Select-Object -First 1
        
        Write-Host "Endpoint: $firstPath" -ForegroundColor Yellow
        Write-Host "Summary: $($firstOperation.summary)" -ForegroundColor White
        Write-Host "Description: $($firstOperation.description)" -ForegroundColor White
        Write-Host "Tags: $($firstOperation.tags -join ', ')" -ForegroundColor White
        Write-Host "Parameters: $($firstOperation.parameters.Count)" -ForegroundColor White
    }
    
    Write-Host "Generation completed!" -ForegroundColor Green
}
catch {
    Write-Error "Failed to generate OpenAPI specification: $($_.Exception.Message)"
    exit 1
}
