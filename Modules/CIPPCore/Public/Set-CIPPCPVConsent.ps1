function Set-CIPPCPVConsent {
    [CmdletBinding()]
    param(
        $Tenantfilter,
        $APIName = "CPV Consent",
        $ExecutingUser
    )
    $Results = [System.Collections.ArrayList]@()
    Set-Location (Get-Item $PSScriptRoot).Parent.FullName
    $ExpectedPermissions = Get-Content '.\Cache_SAMSetup\SAMManifest.json' | ConvertFrom-Json
    $Translator = Get-Content '.\Cache_SAMSetup\PermissionsTranslator.json' | ConvertFrom-Json
    try {
        $ServicePrincipalList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=AppId,id,displayName&`$top=999" -tenantid $Tenantfilter
        $ourSVCPrincipal = $ServicePrincipalList | Where-Object -Property AppId -EQ $env:ApplicationID
    }
    catch {
    
    }
    if (!$ourSVCPrincipal) {
        try {
            $AppBody = @"
{
  "ApplicationGrants":[ {"EnterpriseApplicationId":"00000003-0000-0000-c000-000000000000","Scope":"Application.ReadWrite.all,DelegatedPermissionGrant.ReadWrite.All"}],
  "ApplicationId": "ed2d757e-dbab-439c-a2d3-1567de12d31f"
}
"@
            $CPVConsent = New-GraphpostRequest -body $AppBody -Type POST -noauthcheck $true -uri "https://api.partnercenter.microsoft.com/v1/customers/$($TenantFilter)/applicationconsents" -scope "https://api.partnercenter.microsoft.com/.default" -tenantid $env:TenantID
            $Results.add("Succesfully added CPV Application")
            $ServicePrincipalList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=AppId,id&`$top=999" -tenantid $Tenantfilter
            $ourSVCPrincipal = $ServicePrincipalList | Where-Object -Property AppId -EQ $env:ApplicationID

        } 
        #TODO: after doing this, write to the table that we have done this for current applicationId, so that we don't ever have to do it again when running on a schedule.

        catch {
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Could not add our Service Principal to the client tenant: $($_.Exception.message)" -Sev "Error" -tenant $($Tenantfilter)
            return @("Could not add our Service Principal to the client tenant $($Tenantfilter): $($_.Exception.message)")
        }

    }
    else {
        $Results.add("Application Exists, adding permissions")
    }
    #TODO: Add this as a function so we can use it for more than just our app
    $CurrentRoles = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals/$($ourSVCPrincipal.id)/appRoleAssignments" -tenantid $tenantfilter

    $Grants = foreach ($App in $ExpectedPermissions.requiredResourceAccess) {  
        $svcPrincipalId = $ServicePrincipalList | Where-Object -Property AppId -EQ $app.resourceAppId
        if (!$svcPrincipalId) { continue } #If the app does not exist, we can't add permissions for it. E.g. Defender etc.
        foreach ($SingleResource in $app.ResourceAccess | Where-Object -Property Type -EQ "Role") {
            if ($singleresource.id -In $currentroles.appRoleId) { continue }
            [pscustomobject]@{
                principalId = $($ourSVCPrincipal.id)
                resourceId  = $($svcPrincipalId.id)
                appRoleId   = "$($SingleResource.Id)"
            }
        } 
    } 

    foreach ($Grant in $grants) {
        try {
            $SettingsRequest = New-GraphPOSTRequest -body ($grant | ConvertTo-Json) -uri "https://graph.microsoft.com/beta/servicePrincipals/$($ourSVCPrincipal.id)/appRoleAssignedTo" -tenantid $tenantfilter -type POST
        }
        catch {
            $Results.add("Failed to grant $($grant.appRoleId) to $($grant.resourceId): $($_.Exception.Message)")
        }
    }

    #Adding all required Delegated permissions
    $CurrentDelegatedScopes = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals/$($ourSVCPrincipal.id)/oauth2PermissionGrants" -tenantid $tenantfilter
    foreach ($App in $ExpectedPermissions.requiredResourceAccess) {
        $svcPrincipalId = $ServicePrincipalList | Where-Object -Property AppId -EQ $app.resourceAppId
        if (!$svcPrincipalId) { continue } #If the app does not exist, we can't add permissions for it. E.g. Defender etc.
        $NewScope = ($Translator | Where-Object { $_.id -in $app.ResourceAccess.id } | Where-Object { $_.value -notin 'profile', 'openid', 'offline_access' }).value -join ' '
        $OldScope = ($CurrentDelegatedScopes | Where-Object -Property Resourceid -EQ $svcPrincipalId.id)
        if (!$OldScope) {
            $Createbody = @{
                clientId    = $ourSVCPrincipal.id
                consentType = "AllPrincipals"
                resourceId  = $svcPrincipalId.id
                scope       = $NewScope
            } | ConvertTo-Json -Compress
            $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants" -tenantid $tenantfilter -body $Createbody -type POST
            $Results.add("Succesfully added permissions for $($svcPrincipalId.displayName)")
        }
        else {
            $compare = Compare-Object -ReferenceObject $OldScope.scope.Split(' ') -DifferenceObject $NewScope.Split(' ')
            if (!$compare) {
                $Results.add("All delegated permissions exist for $($svcPrincipalId.displayName)")
                continue
            }
            $Patchbody = @{
                scope = "$NewScope"
            } | ConvertTo-Json -Compress
            $Patchrequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$($Oldscope.id)" -tenantid $tenantfilter -body $Patchbody -type PATCH
            $Results.add("Succesfully updated permissions for $($svcPrincipalId.displayName)")
        }

    }
    return $Results
}