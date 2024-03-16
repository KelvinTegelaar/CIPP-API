using namespace System.Net

Function Invoke-ListLicenses {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $RawGraphRequest = if ($TenantFilter -ne 'AllTenants') {
        $GraphRequest = Get-CIPPLicenseOverview -TenantFilter $TenantFilter | ForEach-Object {
            $TermInfo = $_.TermInfo | ConvertFrom-Json -ErrorAction SilentlyContinue
            $_.TermInfo = $TermInfo
            $_
        }
    } else {
        $Table = Get-CIPPTable -TableName cachelicenses
        $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddHours(-1)
        if (!$Rows) {
            #Push-OutputBinding -Name LicenseQueue -Value (Get-Date).ToString()
            $GraphRequest = [PSCustomObject]@{
                Tenant  = 'Loading data for all tenants. Please check back in 1 minute'
                License = 'Loading data for all tenants. Please check back in 1 minute'
            }
            $Tenants = Get-Tenants -IncludeErrors | ForEach-Object { $_ | Add-Member -NotePropertyName FunctionName -NotePropertyValue 'ListLicensesQueue'; $_ }

            if (($Tenants | Measure-Object).Count -gt 0) {
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'ListLicensesOrchestrator'
                    Batch            = @($Tenants)
                    SkipLog          = $true
                }
                #Write-Host ($InputObject | ConvertTo-Json)
                $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5)
                Write-Host "Started permissions orchestration with ID = '$InstanceId'"
            }
        } else {
            $GraphRequest = $Rows | ForEach-Object {
                $TermInfo = $_.TermInfo | ConvertFrom-Json -ErrorAction SilentlyContinue
                $_.TermInfo = $TermInfo
                $_
            }
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        }) -Clobber

}
