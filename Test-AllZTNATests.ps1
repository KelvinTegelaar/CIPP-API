$Tenant = '7ngn50.onmicrosoft.com'
Get-ChildItem "C:\Github\CIPP-API\Modules\CIPPCore\Public\Tests\Invoke-CippTest*.ps1" | ForEach-Object { . $_.FullName; & $_.BaseName -Tenant $Tenant }
