using namespace System.Net

Function Invoke-GetCippAlerts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Alerts = [System.Collections.Generic.List[object]]::new()
    $Table = Get-CippTable -tablename CippAlerts
    $PartitionKey = Get-Date -UFormat '%Y%m%d'
    $Filter = "PartitionKey eq '{0}'" -f $PartitionKey
    $Rows = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Sort-Object TableTimestamp -Descending | Select-Object -First 10
    $role = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($request.headers.'x-ms-client-principal')) | ConvertFrom-Json).userRoles

    $CIPPVersion = $Request.Query.localversion
    $Version = Assert-CippVersion -CIPPVersion $CIPPVersion
    if ($Version.OutOfDateCIPP) {
        $Alerts.Add(@{Alert = 'Your CIPP Frontend is out of date. Please update to the latest version. Find more on the following '; link = 'https://docs.cipp.app/setup/installation/updating'; type = 'warning' })
        Write-LogMessage -message 'Your CIPP Frontend is out of date. Please update to the latest version' -API 'Updates' -tenant 'All Tenants' -sev Alert

    }
    if ($Version.OutOfDateCIPPAPI) {
        $Alerts.Add(@{Alert = 'Your CIPP API is out of date. Please update to the latest version. Find more on the following'; link = 'https://docs.cipp.app/setup/installation/updating'; type = 'warning' })
        Write-LogMessage -message 'Your CIPP API is out of date. Please update to the latest version' -API 'Updates' -tenant 'All Tenants' -sev Alert
    }

    if ($env:ApplicationID -eq 'LongApplicationID' -or $null -eq $ENV:ApplicationID) { $Alerts.Add(@{Alert = 'You have not yet completed your SAM Setup. Please go to the SAM Setup Wizard in settings to connect CIPP to your tenant.'; link = '/cipp/setup'; type = 'warning' }) }
    if ($role -like '*superadmin*') { $Alerts.Add(@{Alert = 'You are logged in under a superadmin account. This account should not be used for normal usage.'; link = 'https://docs.cipp.app/setup/installation/owntenant'; type = 'danger' }) }
    if ($env:WEBSITE_RUN_FROM_PACKAGE -ne '1' -and $env:AzureWebJobsStorage -ne 'UseDevelopmentStorage=true') {
        $Alerts.Add(
            @{Alert  = 'Your Function App is running in write mode. This will cause performance issues and increase cost. Please check this '
                link = 'https://docs.cipp.app/setup/installation/runfrompackage'
                type = 'warning'
            })
    }
    if ($Rows) { $Rows | ForEach-Object { $Alerts.Add($_) } }
    $Alerts = @($Alerts)
    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Alerts
        })

}
