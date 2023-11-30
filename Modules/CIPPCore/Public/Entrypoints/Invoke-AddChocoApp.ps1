    using namespace System.Net

    Function Invoke-AddChocoApp {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

        $APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

Write-Host "PowerShell HTTP trigger function processed a request."
$ChocoApp = $request.body
$intuneBody = Get-Content "AddChocoApp\choco.app.json" | ConvertFrom-Json
$assignTo = $Request.body.AssignTo
$intuneBody.description = $ChocoApp.description
$intuneBody.displayName = $chocoapp.ApplicationName
$intuneBody.installExperience.runAsAccount = if ($ChocoApp.InstallAsSystem) { "system" } else { "user" }
$intuneBody.installExperience.deviceRestartBehavior = if ($ChocoApp.DisableRestart) { "suppress" } else { "allow" }
$intuneBody.installCommandLine = "powershell.exe -executionpolicy bypass .\Install.ps1 -InstallChoco -Packagename $($chocoapp.PackageName)"
if ($ChocoApp.customrepo) {
    $intuneBody.installCommandLine = $intuneBody.installCommandLine + " -CustomRepo $($chocoapp.CustomRepo)"
}
$intuneBody.UninstallCommandLine = "powershell.exe -executionpolicy bypass .\Uninstall.ps1 -Packagename $($chocoapp.PackageName)"
$intunebody.detectionRules[0].path = "$($ENV:SystemDrive)\programdata\chocolatey\lib"
$intunebody.detectionRules[0].fileOrFolderName = "$($chocoapp.PackageName)"

$Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
$Results = foreach ($Tenant in $tenants) {
    try {
        $CompleteObject = [PSCustomObject]@{
            tenant             = $tenant
            Applicationname    = $ChocoApp.ApplicationName
            assignTo           = $assignTo
            InstallationIntent = $request.body.InstallationIntent
            IntuneBody         = $intunebody
        } | ConvertTo-Json -Depth 15
        $Table = Get-CippTable -tablename 'apps'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$CompleteObject"
            RowKey       = "$((New-Guid).GUID)"
            PartitionKey = "apps"
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

    }
