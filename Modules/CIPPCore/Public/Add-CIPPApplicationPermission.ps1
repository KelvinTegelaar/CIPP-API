function Add-CIPPApplicationPermission {
    [CmdletBinding()]
    param(
        $RequiredResourceAccess,
        $ApplicationId,
        $Tenantfilter
    )
    if ($ApplicationId -eq $env:ApplicationID -and $Tenantfilter -eq $env:TenantID) {
        #return @('Cannot modify application permissions for CIPP-SAM on partner tenant')
        $RequiredResourceAccess = 'CIPPDefaults'
    }
    Set-Location (Get-Item $PSScriptRoot).FullName
    if ($RequiredResourceAccess -eq 'CIPPDefaults') {
        #$RequiredResourceAccess = (Get-Content '.\SAMManifest.json' | ConvertFrom-Json).requiredResourceAccess

        $Permissions = Get-CippSamPermissions -NoDiff
        $RequiredResourceAccess = [System.Collections.Generic.List[object]]::new()

        foreach ($AppId in $Permissions.Permissions.PSObject.Properties.Name) {
            $AppPermissions = @($Permissions.Permissions.$AppId.applicationPermissions)
            $Resource = @{
                resourceAppId  = $AppId
                resourceAccess = [System.Collections.Generic.List[object]]::new()
            }
            foreach ($Permission in $AppPermissions) {
                $Resource.ResourceAccess.Add(@{
                        id   = $Permission.id
                        type = 'Role'
                    })
            }

            $RequiredResourceAccess.Add($Resource)
        }
    }
    $ServicePrincipalList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=AppId,id,displayName&`$top=999" -skipTokenCache $true -tenantid $Tenantfilter -NoAuthCheck $true
    $ourSVCPrincipal = $ServicePrincipalList | Where-Object -Property AppId -EQ $ApplicationId
    if (!$ourSVCPrincipal) {
        #Our Service Principal isn't available yet. We do a sleep and reexecute after 3 seconds.
        Start-Sleep -Seconds 5
        $ServicePrincipalList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=AppId,id,displayName&`$top=999" -skipTokenCache $true -tenantid $Tenantfilter -NoAuthCheck $true
        $ourSVCPrincipal = $ServicePrincipalList | Where-Object -Property AppId -EQ $ApplicationId
    }

    $Results = [System.Collections.Generic.List[string]]::new()

    $CurrentRoles = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals/$($ourSVCPrincipal.id)/appRoleAssignments" -tenantid $Tenantfilter -skipTokenCache $true -NoAuthCheck $true

    $Grants = foreach ($App in $RequiredResourceAccess) {
        $svcPrincipalId = $ServicePrincipalList | Where-Object -Property AppId -EQ $App.resourceAppId
        if (!$svcPrincipalId) {
            try {
                $Body = @{
                    appId = $App.resourceAppId
                } | ConvertTo-Json -Compress
                $svcPrincipalId = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/servicePrincipals' -tenantid $Tenantfilter -body $Body -type POST
            } catch {
                $Results.add("Failed to create service principal for $($App.resourceAppId): $(Get-NormalizedError -message $_.Exception.Message)")
                continue
            }
        }
        foreach ($SingleResource in $App.ResourceAccess | Where-Object -Property Type -EQ 'Role') {
            if ($SingleResource.id -In $CurrentRoles.appRoleId) { continue }
            [pscustomobject]@{
                principalId = $($ourSVCPrincipal.id)
                resourceId  = $($svcPrincipalId.id)
                appRoleId   = "$($SingleResource.Id)"
            }
        }
    }
    $counter = 0
    foreach ($Grant in $Grants) {
        try {
            $SettingsRequest = New-GraphPOSTRequest -body (ConvertTo-Json -InputObject $Grant -Depth 5) -uri "https://graph.microsoft.com/beta/servicePrincipals/$($ourSVCPrincipal.id)/appRoleAssignedTo" -tenantid $Tenantfilter -type POST -NoAuthCheck $true
            $counter++
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            $Results.add("Failed to grant $($Grant.appRoleId) to $($Grant.resourceId): $ErrorMessage")
        }
    }
    "Added $counter Application permissions to $($ourSVCPrincipal.displayName)"
    return $Results
}
