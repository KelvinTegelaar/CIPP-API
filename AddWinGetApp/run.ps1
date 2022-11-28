using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
Set-Location (Get-Item $PSScriptRoot).Parent.FullName

Write-Host "PowerShell HTTP trigger function processed a request."
$WinGetApp = $request.body
if ($ChocoApp.InstallAsSystem) { "system" } else { "user" }

$WinGetData = @{
    "@odata.type"       = "#microsoft.graph.winGetApp"
    "displayName"       = "$($WinGetApp.ApplicationName)"
    "description"       = "$($WinGetApp.description)"
    "packageIdentifier" = "$($WinGetApp.PackageName)"
    "installExperience" = @{
        "@odata.type"  = "microsoft.graph.winGetAppInstallExperience"
        "runAsAccount" = if ($WinGetApp.InstallAsSystem) { "system" } else { "user" }
    }
}

$Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
$Results = foreach ($Tenant in $tenants) {
    try {
        $CompleteObject = [PSCustomObject]@{
            tenant          = $tenant
            Applicationname = $WinGetApp.ApplicationName
            assignTo        = $assignTo
            type            = 'WinGet'
            IntuneBody      = $WinGetData
        } | ConvertTo-Json -Depth 15
        $Table = Get-CippTable -tablename 'apps'
        $Table.Force = $true
        Add-AzDataTableEntity @Table -Entity @{
            JSON         = "$CompleteObject"
            RowKey       = "$((New-Guid).GUID)"
            PartitionKey = "apps"
            status       = "Not Deployed yet"
        }
        "Successfully added Choco App for $($Tenant) to queue."
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Chocolatey Application $($intunebody.Displayname) queued to add" -Sev "Info"
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal'  -API $APINAME -tenant $tenant -message "Failed to add Chocolatey Application $($intunebody.Displayname) to queue" -Sev "Error"
        "Failed added Choco App for $($Tenant) to queue"
    }
}

$body = [pscustomobject]@{"Results" = $results }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
