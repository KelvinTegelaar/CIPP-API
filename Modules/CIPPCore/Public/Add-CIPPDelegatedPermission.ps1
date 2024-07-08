function Add-CIPPDelegatedPermission {
    [CmdletBinding()]
    param(
        $RequiredResourceAccess,
        $ApplicationId,
        $NoTranslateRequired,
        $Tenantfilter
    )
    Write-Host 'Adding Delegated Permissions'
    Set-Location (Get-Item $PSScriptRoot).FullName

    if ($ApplicationId -eq $ENV:ApplicationID -and $Tenantfilter -eq $env:TenantID) {
        #return @('Cannot modify delgated permissions for CIPP-SAM on partner tenant')
        $RequiredResourceAccess = 'CIPPDefaults'
    }

    if ($RequiredResourceAccess -eq 'CIPPDefaults') {
        $RequiredResourceAccess = (Get-Content '.\SAMManifest.json' | ConvertFrom-Json).requiredResourceAccess
        $AdditionalPermissions = Get-Content '.\AdditionalPermissions.json' | ConvertFrom-Json

        if ($Tenantfilter -eq $env:TenantID) {
            $RequiredResourceAccess = $RequiredResourceAccess + ($AdditionalPermissions | Where-Object { $RequiredResourceAccess.resourceAppId -notcontains $_.resourceAppId })
        } else {
            # remove the partner center permission if not pushing to partner tenant
            $RequiredResourceAccess = $RequiredResourceAccess | Where-Object { $_.resourceAppId -ne 'fa3d9a0c-3fb0-42cc-9193-47c7ecd2edbd' }
        }
        $RequiredResourceAccess = $RequiredResourceAccess + ($AdditionalPermissions | Where-Object { $RequiredResourceAccess.resourceAppId -notcontains $_.resourceAppId })
    }
    $Translator = Get-Content '.\PermissionsTranslator.json' | ConvertFrom-Json
    $ServicePrincipalList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=AppId,id,displayName&`$top=999" -tenantid $Tenantfilter -skipTokenCache $true -NoAuthCheck $true
    $ourSVCPrincipal = $ServicePrincipalList | Where-Object -Property AppId -EQ $ApplicationId
    $Results = [System.Collections.ArrayList]@()

    $CurrentDelegatedScopes = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals/$($ourSVCPrincipal.id)/oauth2PermissionGrants" -skipTokenCache $true -tenantid $Tenantfilter -NoAuthCheck $true

    foreach ($App in $RequiredResourceAccess) {
        $svcPrincipalId = $ServicePrincipalList | Where-Object -Property AppId -EQ $App.resourceAppId
        $AdditionalScopes = ($AdditionalPermissions | Where-Object -Property resourceAppId -EQ $App.resourceAppId).resourceAccess
        if (!$svcPrincipalId) { continue }
        if ($AdditionalScopes) {
            $NewScope = (@(($Translator | Where-Object { $_.id -in $App.ResourceAccess.id }).value) + @($AdditionalScopes.id | Select-Object -Unique)) -join ' '
        } else {
            if ($NoTranslateRequired) {
                $NewScope = $App.resourceAccess | ForEach-Object { $_.id } -join ' '
            } else {
                $NewScope = ($Translator | Where-Object { $_.id -in $App.resourceAccess.id }).value -join ' '
            }
            $NewScope = ($Translator | Where-Object { $_.id -in $App.ResourceAccess.id }).value -join ' '
        }

        $OldScope = ($CurrentDelegatedScopes | Where-Object -Property Resourceid -EQ $svcPrincipalId.id)

        if (!$OldScope) {
            $Createbody = @{
                clientId    = $ourSVCPrincipal.id
                consentType = 'AllPrincipals'
                resourceId  = $svcPrincipalId.id
                scope       = $NewScope
            } | ConvertTo-Json -Compress
            $CreateRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' -tenantid $Tenantfilter -body $Createbody -type POST -NoAuthCheck $true
            $Results.add("Successfully added permissions for $($svcPrincipalId.displayName)") | Out-Null
        } else {
            $compare = Compare-Object -ReferenceObject $OldScope.scope.Split(' ') -DifferenceObject $NewScope.Split(' ')
            if (!$compare) {
                $Results.add("All delegated permissions exist for $($svcPrincipalId.displayName): $($NewScope)") | Out-Null
                continue
            }
            $Patchbody = @{
                scope = "$NewScope"
            } | ConvertTo-Json -Compress
            $Patchrequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$($OldScope.id)" -tenantid $Tenantfilter -body $Patchbody -type PATCH -NoAuthCheck $true
            $Results.add("Successfully updated permissions for $($svcPrincipalId.displayName): $($NewScope)") | Out-Null
        }
    }

    return $Results
}
