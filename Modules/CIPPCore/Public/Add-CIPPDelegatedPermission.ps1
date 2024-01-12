function Add-CIPPDelegatedPermission {
    [CmdletBinding()]
    param(
        $RequiredResourceAccess,
        $ApplicationId,
        $Tenantfilter
    )
    Write-Host 'Adding Delegated Permissions'
    Set-Location (Get-Item $PSScriptRoot).FullName

    if ($ApplicationId -eq $ENV:ApplicationID -and $Tenantfilter -eq $env:TenantID) {
        return @('Cannot modify delgated permissions for CIPP-SAM on partner tenant')
    }

    if ($RequiredResourceAccess -eq 'CIPPDefaults') {
        $RequiredResourceAccess = (Get-Content '.\SAMManifest.json' | ConvertFrom-Json).requiredResourceAccess
    }
    $Translator = Get-Content '.\PermissionsTranslator.json' | ConvertFrom-Json
    $ServicePrincipalList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=AppId,id,displayName&`$top=999" -tenantid $Tenantfilter -skipTokenCache $true
    $ourSVCPrincipal = $ServicePrincipalList | Where-Object -Property AppId -EQ $ApplicationId
    $Results = [System.Collections.ArrayList]@()

    $CurrentDelegatedScopes = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals/$($ourSVCPrincipal.id)/oauth2PermissionGrants" -skipTokenCache $true -tenantid $Tenantfilter

    foreach ($App in $requiredResourceAccess) {
        $svcPrincipalId = $ServicePrincipalList | Where-Object -Property AppId -EQ $App.resourceAppId
        if (!$svcPrincipalId) { continue }
        $NewScope = ($Translator | Where-Object { $_.id -in $App.ResourceAccess.id } | Where-Object { $_.value -notin 'profile', 'openid', 'offline_access' }).value -join ' '
        $OldScope = ($CurrentDelegatedScopes | Where-Object -Property Resourceid -EQ $svcPrincipalId.id)

        if (!$OldScope) {
            $Createbody = @{
                clientId    = $ourSVCPrincipal.id
                consentType = 'AllPrincipals'
                resourceId  = $svcPrincipalId.id
                scope       = $NewScope
            } | ConvertTo-Json -Compress
            $CreateRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' -tenantid $Tenantfilter -body $Createbody -type POST
            $Results.add("Successfully added permissions for $($svcPrincipalId.displayName)") | Out-Null
        } else {
            $compare = Compare-Object -ReferenceObject $OldScope.scope.Split(' ') -DifferenceObject $NewScope.Split(' ')
            if (!$compare) {
                $Results.add("All delegated permissions exist for $($svcPrincipalId.displayName)") | Out-Null
                continue
            }
            $Patchbody = @{
                scope = "$NewScope"
            } | ConvertTo-Json -Compress
            $Patchrequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$($OldScope.id)" -tenantid $Tenantfilter -body $Patchbody -type PATCH
            $Results.add("Successfully updated permissions for $($svcPrincipalId.displayName)") | Out-Null
        }
    }

    return $Results
}
