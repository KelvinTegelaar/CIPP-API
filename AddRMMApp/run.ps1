using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


Write-Host "PowerShell HTTP trigger function processed a request."
$RMMApp = $request.body
$intuneBody = Get-Content "AddRMMApp\$($RMMApp.RMMName).app.json" | ConvertFrom-Json
$assignTo = $Request.body.AssignTo
$intuneBody.displayName = $RMMApp.ApplicationName
$intuneBody.installCommandLine = "powershell.exe -executionpolicy bypass .\Install.ps1 -InstallChoco -Packagename $($RMMApp.PackageName)"
$intuneBody.UninstallCommandLine = "powershell.exe -executionpolicy bypass .\Uninstall.ps1 -Packagename $($RMMApp.PackageName)"

$Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
$Results = foreach ($Tenant in $tenants) {
    try {
        $CompleteObject = [PSCustomObject]@{
            tenant          = $tenant
            Applicationname = $RMMApp.ApplicationName
            assignTo        = $assignTo
            IntuneBody      = $intunebody
        } | ConvertTo-Json -Depth 15
        $JSONFile = New-Item -Path ".\ChocoApps.Cache\$(New-Guid)" -Value $CompleteObject -Force -ErrorAction Stop
        "Succesfully added MSP App for $($Tenant) to queue."
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "MSP Application $($intunebody.Displayname) queued to add" -Sev "Info"
    }
    catch {
        Log-Request -user $request.headers.'x-ms-client-principal'  -API $APINAME -tenant $tenant -message "Failed to add MSP Application $($intunebody.Displayname) to queue" -Sev "Error"
        "Failed to add MSP app for $($Tenant) to queue"
    }
}

$body = [pscustomobject]@{"Results" = $results }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
