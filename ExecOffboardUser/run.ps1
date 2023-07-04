using namespace System.Net
# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
try {
    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
    $Username = $request.body.user
    $Tenantfilter = $request.body.tenantfilter
    if ($username -eq $null) { exit }
    $userid = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($username)" -tenantid $Tenantfilter).id
    Set-Location (Get-Item $PSScriptRoot).Parent.FullName
    $ConvertTable = Import-Csv Conversiontable.csv | Sort-Object -Property 'guid' -Unique

    Write-Host ($request.body | ConvertTo-Json)
    $results = switch ($request.body) {
        { $_."ConvertToShared" -eq 'true' } {
            Set-CIPPMailboxType -ExecutingUser $request.headers.'x-ms-client-principal' -tenantFilter $tenantFilter -userid $username -username $username -MailboxType "Shared" -APIName "ExecOffboardUser"
        }
        { $_.RevokeSessions -eq 'true' } { 
            Revoke-CIPPSessions -tenantFilter $tenantFilter -username $username -userid $userid -ExecutingUser $request.headers.'x-ms-client-principal' -APIName "ExecOffboardUser"
        }
        { $_.ResetPass -eq 'true' } { 
            Set-CIPPResetPassword -tenantFilter $tenantFilter -userid $username -ExecutingUser $request.headers.'x-ms-client-principal' -APIName "ExecOffboardUser"
        }
        { $_.RemoveGroups -eq 'true' } { 
            Remove-CIPPGroups -userid $userid -tenantFilter $Tenantfilter -ExecutingUser $request.headers.'x-ms-client-principal' -APIName "ExecOffboardUser"
        }

        { $_."HideFromGAL" -eq 'true' } {
            Set-CIPPHideFromGAL -tenantFilter $tenantFilter -userid $username -HideFromGAL $true -ExecutingUser $request.headers.'x-ms-client-principal' -APIName "ExecOffboardUser"
        }
        { $_."DisableSignIn" -eq 'true' } {
            Set-CIPPSignInState -TenantFilter $tenantFilter -userid $username -AccountEnabled $false -ExecutingUser $request.headers.'x-ms-client-principal' -APIName "ExecOffboardUser"
        }

        { $_."OnedriveAccess" -ne "" } { 
            Set-CIPPOnedriveAccess -tenantFilter $tenantFilter -userid $username -OnedriveAccessUser $request.body.OnedriveAccess -ExecutingUser $request.headers.'x-ms-client-principal' -APIName "ExecOffboardUser"
        }
        { $_."AccessNoAutomap" -ne "" } { 
            Set-CIPPMailboxAccess -tenantFilter $tenantFilter -userid $username -AccessUser $request.body.AccessNoAutomap -Automap $true -AccessRights @("FullAccess") -ExecutingUser $request.headers.'x-ms-client-principal' -APIName "ExecOffboardUser"
        }
        { $_."AccessAutomap" -ne "" } { 
            Set-CIPPMailboxAccess -tenantFilter $tenantFilter -userid $username -AccessUser $request.body.AccessNoAutomap -Automap $false -AccessRights @("FullAccess") -ExecutingUser $request.headers.'x-ms-client-principal' -APIName "ExecOffboardUser"
        }
    
        { $_."OOO" -ne "" } { 
            Set-CIPPOutOfOffice -tenantFilter $tenantFilter -userid $username -OOO $request.body.OOO -ExecutingUser $request.headers.'x-ms-client-principal' -APIName "ExecOffboardUser"
        }
        { $_."forward" -ne "" } { 
            Set-CIPPForwarding -userid $userid -username $username -tenantFilter $Tenantfilter -Forward $request.body.forward -KeepCopy [bool]$request.body.keepCopy -ExecutingUser $request.headers.'x-ms-client-principal' -APIName "ExecOffboardUser"
        }
        { $_."RemoveLicenses" -eq 'true' } {
            Remove-CIPPLicense -userid $userid -username $Username -tenantFilter $Tenantfilter -ExecutingUser $request.headers.'x-ms-client-principal' -APIName "ExecOffboardUser"
        }

        { $_."Deleteuser" -eq 'true' } {
            Remove-CIPPUser -userid $userid -username $Username -tenantFilter $Tenantfilter -ExecutingUser $request.headers.'x-ms-client-principal' -APIName "ExecOffboardUser"
        }

        { $_."RemoveRules" -eq 'true' } {
            Remove-CIPPRules -userid $userid -username $Username -tenantFilter $Tenantfilter -ExecutingUser $request.headers.'x-ms-client-principal' -APIName "ExecOffboardUser"
        }

        { $_."RemoveMobile" -eq 'true' } {
            Remove-CIPPMobileDevice -userid $userid -username $Username -tenantFilter $Tenantfilter -ExecutingUser $request.headers.'x-ms-client-principal' -APIName "ExecOffboardUser"
        }
    
    }
    $StatusCode = [HttpStatusCode]::OK
    $body = [pscustomobject]@{"Results" = @($results) }
}
catch {
    $StatusCode = [HttpStatusCode]::Forbidden
    $body = $_.Exception.message
}
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    }) 
