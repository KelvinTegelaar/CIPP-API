using namespace System.Net

function Invoke-ListLicenses {
    <#
    .SYNOPSIS
    List Microsoft 365 licenses for tenants
    
    .DESCRIPTION
    Retrieves license information including usage, availability, and term details for Microsoft 365 tenants
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
        
    .NOTES
    Group: Tenant Reports
    Summary: List Licenses
    Description: Retrieves comprehensive license information including usage statistics, availability, and term details for Microsoft 365 tenants
    Tags: Tenant,Reports,Licenses
    Parameter: tenantFilter (string) [query] - The tenant to retrieve license information for (use 'AllTenants' for all tenants)
    Response: Returns an array of license objects with the following properties:
    Response: - Tenant (string): Tenant identifier or domain name
    Response: - License (string): License name or SKU identifier
    Response: - TermInfo (object): License term information including start date, end date, and renewal details
    Response: - TotalUnits (number): Total number of licenses purchased
    Response: - ConsumedUnits (number): Number of licenses currently in use
    Response: - AvailableUnits (number): Number of licenses available for assignment
    Response: - WarningUnits (number): Number of licenses in warning state
    Response: - ErrorUnits (number): Number of licenses in error state
    Response: When tenantFilter='AllTenants' and data is loading:
    Response: - Tenant (string): Loading message
    Response: - License (string): Loading message
    Example: [
      {
        "Tenant": "contoso.onmicrosoft.com",
        "License": "Microsoft 365 Business Premium",
        "TermInfo": {
          "StartDate": "2024-01-01T00:00:00Z",
          "EndDate": "2024-12-31T23:59:59Z",
          "RenewalDate": "2024-12-31T23:59:59Z"
        },
        "TotalUnits": 100,
        "ConsumedUnits": 75,
        "AvailableUnits": 25,
        "WarningUnits": 0,
        "ErrorUnits": 0
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $RawGraphRequest = if ($TenantFilter -ne 'AllTenants') {
        $GraphRequest = Get-CIPPLicenseOverview -TenantFilter $TenantFilter | ForEach-Object {
            $TermInfo = $_.TermInfo | ConvertFrom-Json -ErrorAction SilentlyContinue
            $_.TermInfo = $TermInfo
            $_
        }
    }
    else {
        $Table = Get-CIPPTable -TableName cachelicenses
        $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddHours(-1)
        if (!$Rows) {
            $GraphRequest = [PSCustomObject]@{
                Tenant  = 'Loading data for all tenants. Please check back in 1 minute'
                License = 'Loading data for all tenants. Please check back in 1 minute'
            }
            $Tenants = Get-Tenants -IncludeErrors

            if (($Tenants | Measure-Object).Count -gt 0) {
                $Queue = New-CippQueueEntry -Name 'Licenses (All Tenants)' -TotalTasks ($Tenants | Measure-Object).Count
                $Tenants = $Tenants | Select-Object customerId, defaultDomainName, @{Name = 'QueueId'; Expression = { $Queue.RowKey } }, @{Name = 'FunctionName'; Expression = { 'ListLicensesQueue' } }, @{Name = 'QueueName'; Expression = { $_.defaultDomainName } }
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'ListLicensesOrchestrator'
                    Batch            = @($Tenants)
                    SkipLog          = $true
                }
                #Write-Host ($InputObject | ConvertTo-Json)
                $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
                Write-Host "Started permissions orchestration with ID = '$InstanceId'"
            }
        }
        else {
            $GraphRequest = $Rows | Where-Object { $_.License } | ForEach-Object {
                if ($_.TermInfo) {
                    $TermInfo = $_.TermInfo | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $_.TermInfo = $TermInfo
                }
                else {
                    $_ | Add-Member -NotePropertyName TermInfo -NotePropertyValue $null
                }
                $_
            }
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        }) -Clobber

}
