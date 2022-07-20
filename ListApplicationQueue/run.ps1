using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

$QueuedApps = Get-ChildItem "ChocoApps.Cache\"

$CurrentStandards = foreach ($QueueFile in $QueuedApps) {
    $ApplicationFile = Get-Content "$($QueueFile)" | ConvertFrom-Json
    if ($ApplicationFile.Tenant -eq $null) { continue }
    [PSCustomObject]@{
        tenantName      = $ApplicationFile.tenant
        applicationName = $ApplicationFile.Applicationname
        cmdLine         = $ApplicationFile.IntuneBody.installCommandLine
        assignTo        = $ApplicationFile.assignTo
        id              = $($QueueFile.name)
    }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($CurrentStandards)
    })
