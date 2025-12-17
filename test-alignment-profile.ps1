# Test script for Get-CIPPTenantAlignment with profiling
# This will verify the function returns data in the same format

# Import the module
Import-Module "$PSScriptRoot\Modules\CIPPCore" -Force

# Test with a single tenant
$TestTenant = 'm365x72497814.onmicrosoft.com' # Replace with a valid test tenant

Write-Host "Testing Get-CIPPTenantAlignment with profiling..." -ForegroundColor Cyan
Write-Host "Tenant: $TestTenant" -ForegroundColor Yellow

try {
    $Result = Get-CIPPTenantAlignment -TenantFilter $TestTenant
    
    Write-Host "`nResult Count: $($Result.Count)" -ForegroundColor Green
    
    if ($Result) {
        Write-Host "`nFirst Result Properties:" -ForegroundColor Green
        $Result[0] | Get-Member -MemberType Properties | Select-Object Name, Definition
        
        Write-Host "`nFirst Result Data:" -ForegroundColor Green
        $Result[0] | ConvertTo-Json -Depth 2
    } else {
        Write-Host "No results returned" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
}
