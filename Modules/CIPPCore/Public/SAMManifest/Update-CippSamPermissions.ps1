function Update-CippSamPermissions {
    <#
    .SYNOPSIS
        Repairs the CIPP-SAM app registration permissions in the partner tenant.
    .DESCRIPTION
        Diffs the effective CIPP-SAM permission set (manifest defaults + saved extras) against the live
        CIPP-SAM application registration in the partner tenant and ADDS any missing permissions to the
        app registration's requiredResourceAccess. This is additive only: it never removes permissions,
        so it cannot strip a legitimately-configured entry. Extra permissions found on the app that are
        not part of the effective set are reported back so an admin can review/remove them manually.

        Pushing these permissions out to customer tenants is handled separately by the CPV refresh.
    .PARAMETER UpdatedBy
        The user or system that is performing the update. Defaults to 'CIPP-API'.
    .OUTPUTS
        String indicating the result of the operation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$UpdatedBy = 'CIPP-API'
    )

    try {
        $CurrentPermissions = Get-CippSamPermissions
        $PartnerAppDiff = $CurrentPermissions.PartnerAppDiff
        $MissingPermissions = $CurrentPermissions.MissingPermissions

        $MissingAppIds = @($MissingPermissions.PSObject.Properties.Name)
        $ExtraAppIds = @($PartnerAppDiff.PSObject.Properties.Name | Where-Object {
                ($PartnerAppDiff.$_.extraApplicationPermissions | Measure-Object).Count -gt 0 -or
                ($PartnerAppDiff.$_.extraDelegatedPermissions | Measure-Object).Count -gt 0
            })

        if ($MissingAppIds.Count -eq 0) {
            if ($ExtraAppIds.Count -gt 0) {
                $ExtraSummary = foreach ($AppId in $ExtraAppIds) {
                    $Names = @($PartnerAppDiff.$AppId.extraApplicationPermissions.value) + @($PartnerAppDiff.$AppId.extraDelegatedPermissions.value)
                    "$AppId ($($Names -join ', '))"
                }
                return "No missing permissions to add. The following extra permissions are present on the app and should be reviewed/removed manually: $($ExtraSummary -join '; ')"
            }
            return 'No permissions to update'
        }

        # Retrieve the live CIPP-SAM application registration in the partner tenant.
        $PartnerApp = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/applications(appId='$($env:ApplicationID)')?`$select=id,requiredResourceAccess" -tenantid $env:TenantID -NoAuthCheck $true

        $RequiredResourceAccess = [System.Collections.Generic.List[object]]::new()
        foreach ($Resource in $PartnerApp.requiredResourceAccess) {
            $ResourceAccess = [System.Collections.Generic.List[object]]::new()
            foreach ($Access in $Resource.resourceAccess) {
                $ResourceAccess.Add(@{ id = $Access.id; type = $Access.type })
            }
            $RequiredResourceAccess.Add([PSCustomObject]@{
                    resourceAppId  = $Resource.resourceAppId
                    resourceAccess = $ResourceAccess
                })
        }

        $AddedPermissions = [System.Collections.Generic.List[string]]::new()
        foreach ($AppId in $MissingAppIds) {
            $Resource = $RequiredResourceAccess | Where-Object -Property resourceAppId -EQ $AppId | Select-Object -First 1
            if (!$Resource) {
                $Resource = [PSCustomObject]@{
                    resourceAppId  = $AppId
                    resourceAccess = [System.Collections.Generic.List[object]]::new()
                }
                $RequiredResourceAccess.Add($Resource)
            }
            $ExistingIds = @($Resource.resourceAccess.id)

            foreach ($Permission in $MissingPermissions.$AppId.applicationPermissions) {
                if ($Permission.id -and $ExistingIds -notcontains $Permission.id) {
                    $Resource.resourceAccess.Add(@{ id = $Permission.id; type = 'Role' })
                    $AddedPermissions.Add("$($Permission.value) (Application)")
                }
            }
            foreach ($Permission in $MissingPermissions.$AppId.delegatedPermissions) {
                if ($Permission.id -and $ExistingIds -notcontains $Permission.id) {
                    $Resource.resourceAccess.Add(@{ id = $Permission.id; type = 'Scope' })
                    $AddedPermissions.Add("$($Permission.value) (Delegated)")
                }
            }
        }

        if ($AddedPermissions.Count -eq 0) {
            return 'No permissions to update'
        }

        $PatchBody = @{ requiredResourceAccess = @($RequiredResourceAccess) } | ConvertTo-Json -Depth 10 -Compress
        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/applications/$($PartnerApp.id)" -tenantid $env:TenantID -body $PatchBody -type PATCH -NoAuthCheck $true

        Write-LogMessage -API 'UpdateCippSamPermissions' -message "CIPP-SAM app registration permissions repaired by $UpdatedBy" -Sev 'Info' -LogData @{ Added = $AddedPermissions }

        $Result = "Added $($AddedPermissions.Count) missing permission(s) to the CIPP-SAM app registration: $($AddedPermissions -join ', '). Run a CPV refresh to apply these to customer tenants."
        if ($ExtraAppIds.Count -gt 0) {
            $ExtraSummary = foreach ($AppId in $ExtraAppIds) {
                $Names = @($PartnerAppDiff.$AppId.extraApplicationPermissions.value) + @($PartnerAppDiff.$AppId.extraDelegatedPermissions.value)
                "$AppId ($($Names -join ', '))"
            }
            $Result += " Extra permissions present on the app that should be reviewed/removed manually: $($ExtraSummary -join '; ')."
        }
        return $Result
    } catch {
        throw "Failed to update permissions: $($_.Exception.Message)"
    }
}
