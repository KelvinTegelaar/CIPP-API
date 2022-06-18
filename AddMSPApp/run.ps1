using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


Write-Host "PowerShell HTTP trigger function processed a request."
$RMMApp = $request.body
$assignTo = $Request.body.AssignTo
$intuneBody = Get-Content "AddMSPApp\$($RMMApp.RMMName.value).app.json" | ConvertFrom-Json
$intuneBody.displayName = $RMMApp.DisplayName

$Tenants = $request.body.selectedTenants
$Results = foreach ($Tenant in $tenants) {
    $InstallParams = [pscustomobject]$RMMApp.params
    switch ($rmmapp.RMMName.value) {
        'datto' { 
            $installcommandline = "powershell.exe -executionpolicy bypass .\install.ps1 -URL $($InstallParams.DattoURL) -GUID $($InstallParams.DattoGUID["$($tenant.customerId)"])"
            $UninstallCommandLine = "powershell.exe -executionpolicy bypass .\uninstall.ps1"
        }
        'ninja' { 
            $installcommandline = "powershell.exe -executionpolicy bypass .\install.ps1 -InstallParam $($RMMApp.PackageName)"
            $UninstallCommandLine = "powershell.exe -executionpolicy bypass .\uninstall.ps1"
        }
        'Huntress' { 
            $installcommandline = "powershell.exe -executionpolicy bypass .\install.ps1 -OrgKey $($InstallParams.Orgkey["$($tenant.customerId)"]) -acctkey $($InstallParams.AccountKey)"
            $UninstallCommandLine = "powershell.exe -executionpolicy bypass .\install.ps1 -Uninstall"
        }
        'Immybot' { 
            $installcommandline = "powershell.exe -executionpolicy bypass .\install.ps1 -url $($InstallParams.ClientURL["$($tenant.customerId)"])"
            $UninstallCommandLine = "powershell.exe -executionpolicy bypass .\uninstall.ps1"
        }
        'syncro' { 
            $installcommandline = "powershell.exe -executionpolicy bypass .\install.ps1 -URL $($InstallParams.ClientURL["$($tenant.customerId)"])"
            $UninstallCommandLine = "powershell.exe -executionpolicy bypass .\uninstall.ps1"
        }
        'NCentral' { 
            $installcommandline = "powershell.exe -executionpolicy bypass .\install.ps1 -InstallParam $($RMMApp.PackageName)"
            $UninstallCommandLine = "powershell.exe -executionpolicy bypass .\uninstall.ps1"
        }
    }
    $intuneBody.installCommandLine = $installcommandline
    $intuneBody.UninstallCommandLine = $UninstallCommandLine


    try {
        $CompleteObject = [PSCustomObject]@{
            tenant          = $tenant.defaultDomainName
            Applicationname = $RMMApp.DisplayName
            assignTo        = $assignTo
            IntuneBody      = $intunebody
            type            = "MSPApp"
            MSPAppName      = $RMMApp.RMMName.value
        } | ConvertTo-Json -Depth 15
        $JSONFile = New-Item -Path ".\ChocoApps.Cache\$(New-Guid)" -Value $CompleteObject -Force -ErrorAction Stop
        "Succesfully added MSP App for $($Tenant.defaultDomainName) to queue."
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant.defaultDomainName -message "MSP Application $($intunebody.Displayname) queued to add" -Sev "Info"
    }
    catch {
        Log-Request -user $request.headers.'x-ms-client-principal'  -API $APINAME -tenant $tenant.defaultDomainName -message "Failed to add MSP Application $($intunebody.Displayname) to queue" -Sev "Error"
        "Failed to add MSP app for $($Tenant.defaultDomainName) to queue"
    }
}

$body = [pscustomobject]@{"Results" = $results }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
