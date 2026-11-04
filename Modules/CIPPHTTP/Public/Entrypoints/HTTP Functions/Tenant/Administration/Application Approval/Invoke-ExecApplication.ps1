function Invoke-ExecApplication {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $ValidTypes = @('applications', 'servicePrincipals')
    $ValidActions = @('Update', 'Upsert', 'Delete', 'RemoveKey', 'RemovePassword', 'Hide', 'Show', 'ListSigningCertificates', 'AddSigningCertificate', 'SetPreferredSigningKey', 'RemoveSigningCertificate', 'UpdateOwners', 'UpdateAssignments')

    $Id = $Request.Query.Id ?? $Request.Body.Id
    $Type = $Request.Query.Type ?? $Request.Body.Type
    if (-not $Id) {
        $AppId = $Request.Query.AppId ?? $Request.Body.AppId
        if (-not $AppId) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = "Required parameter 'Id' or 'AppId' is missing"
                })
            return
        }
        $IdPath = "(appId='$AppId')"
    } else {
        $IdPath = "/$Id"
    }
    if ($Type -and $ValidTypes -notcontains $Type) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = "Invalid Type specified. Valid types are: $($ValidTypes -join ', ')"
            })
        return
    }

    $Uri = "https://graph.microsoft.com/beta/$($Type)$($IdPath)"
    $Action = $Request.Query.Action ?? $Request.Body.Action

    if ($ValidActions -notcontains $Action) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = "Invalid Action specified. Valid actions are: $($ValidActions -join ', ')"
            })
        return
    }

    if ($Action -eq 'UpdateOwners') {
        if (-not $Type) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = @(@{ resultText = "Type is required for $Action."; state = 'error' }) }
                })
        }
        # The autocomplete posts { label, value } objects; plain id strings are accepted too.
        $Owners = foreach ($Change in @(@{ Adding = $true; Items = $Request.Body.AddOwnerIds }, @{ Adding = $false; Items = $Request.Body.RemoveOwnerIds })) {
            foreach ($Owner in @($Change.Items)) {
                if ($null -eq $Owner) { continue }
                $OwnerId = "$($Owner.value ?? $Owner)"
                [PSCustomObject]@{ Id = $OwnerId; Label = "$($Owner.label ?? $OwnerId)"; Adding = $Change.Adding }
            }
        }
        $InvalidOwners = @($Owners).Where({ $_.Id -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$' })
        if (@($Owners).Count -eq 0 -or $InvalidOwners.Count -gt 0) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = @(@{ resultText = 'Select at least one owner to add or remove.'; state = 'error' }) }
                })
        }
        $SeenOwners = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($Owner in $Owners) {
            if (-not $SeenOwners.Add($Owner.Id)) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ Results = @(@{ resultText = "$($Owner.Label) is selected more than once; it can't be both added and removed."; state = 'error' }) }
                    })
            }
        }
    }

    if ($Action -eq 'UpdateAssignments') {
        $GuidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
        $DefaultAccessRoleId = '00000000-0000-0000-0000-000000000000'
        $InvalidInput = if ($Type -ne 'servicePrincipals') { 'User and group assignments exist only on enterprise applications (Type servicePrincipals).' }
        $AddPrincipals = foreach ($Principal in @(@($Request.Body.AddUserIds) + @($Request.Body.AddGroupIds))) {
            if ($null -eq $Principal) { continue }
            $PrincipalId = "$($Principal.value ?? $Principal)"
            if ($PrincipalId -notmatch $GuidPattern) { $InvalidInput = "'$PrincipalId' is not a user or group id." }
            [PSCustomObject]@{ Id = $PrincipalId; Label = "$($Principal.label ?? $PrincipalId)" }
        }
        $RemoveAssignments = foreach ($Assignment in @($Request.Body.RemoveAssignmentIds)) {
            if ($null -eq $Assignment) { continue }
            $AssignmentId = "$($Assignment.value ?? $Assignment)"
            if ($AssignmentId -notmatch '^[A-Za-z0-9_-]+$') { $InvalidInput = "'$AssignmentId' is not an assignment id." }
            [PSCustomObject]@{ Id = $AssignmentId; Label = "$($Assignment.label ?? $AssignmentId)" }
        }
        $AppRoleId = "$($Request.Body.AppRoleId.value ?? $Request.Body.AppRoleId)"
        if ($AppRoleId -and $AppRoleId -notmatch $GuidPattern) { $InvalidInput = "'$AppRoleId' is not an app role id." }
        $RequiredInput = $Request.Body.AppRoleAssignmentRequired
        $SetRequired = if ($null -ne $RequiredInput -and "$RequiredInput" -ne '') { "$RequiredInput" -eq 'True' }
        if ($InvalidInput) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = @(@{ resultText = $InvalidInput; state = 'error' }) }
                })
        }
    }

    $PostParams = @{
        Uri = $Uri
    }

    if ($Action -eq 'Delete') {
        $PostParams.Type = 'DELETE'
    }
    if ($Action -eq 'Update' -or $Action -eq 'Upsert') {
        $PostParams.Type = 'PATCH'
    }

    if ($Action -eq 'Upsert') {
        $PostParams.AddedHeaders = @{
            'Prefer' = 'create-if-missing'
        }
    }

    if ($Request.Body) {
        # Depth 10 so nested payloads (e.g. web/spa/publicClient redirectUris and implicitGrantSettings) aren't truncated.
        $PostParams.Body = $Request.Body.Payload | ConvertTo-Json -Depth 10 -Compress
    }

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    try {
        if ($Action -eq 'RemoveKey' -or $Action -eq 'RemovePassword') {
            # Handle credential removal
            $KeyIds = $Request.Body.KeyIds.value ?? $Request.Body.KeyIds
            if (-not $KeyIds -or $KeyIds.Count -eq 0) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = "KeyIds parameter is required for $Action action"
                    })
                return
            }

            if ($Action -eq 'RemoveKey') {
                # For key credentials, use a single PATCH request
                $CurrentObject = New-GraphGetRequest -Uri $Uri -tenantid $TenantFilter -AsApp $true
                $UpdatedKeyCredentials = $CurrentObject.keyCredentials | Where-Object { $_.keyId -notin $KeyIds }
                $PatchBody = @{
                    keyCredentials = @($UpdatedKeyCredentials)
                }

                $Response = New-GraphPOSTRequest -Uri $Uri -Type 'PATCH' -Body ($PatchBody | ConvertTo-Json -Depth 10) -tenantid $TenantFilter -AsApp $true

                $Results = @{
                    resultText = "Successfully removed $($KeyIds.Count) key credential(s) from $Type"
                    state      = 'success'
                    details    = @($Response)
                }
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results.resultText -Sev 'Info'
            } else {
                # For password credentials, use bulk removePassword requests
                $BulkRequests = foreach ($KeyId in $KeyIds) {
                    $RemoveBody = @{
                        keyId = $KeyId
                    }

                    @{
                        id      = $KeyId
                        method  = 'POST'
                        url     = "$($Type)$($IdPath)/removePassword"
                        body    = $RemoveBody
                        headers = @{
                            'Content-Type' = 'application/json'
                        }
                    }
                }

                $BulkResults = New-GraphBulkRequest -Requests @($BulkRequests) -tenantid $TenantFilter -AsApp $true

                $SuccessCount = ($BulkResults | Where-Object { $_.status -eq 204 }).Count
                $FailureCount = ($BulkResults | Where-Object { $_.status -ne 204 }).Count

                $Results = @{
                    resultText = "Bulk RemovePassword completed. Success: $SuccessCount, Failures: $FailureCount"
                    state      = if ($FailureCount -eq 0) { 'success' } else { 'error' }
                    details    = @($BulkResults)
                }
                if ($FailureCount -eq 0) {
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results.resultText -Sev 'Info'
                } else {
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results.resultText -Sev 'Error'
                }
            }
        } elseif ($Action -in @('ListSigningCertificates', 'AddSigningCertificate', 'SetPreferredSigningKey', 'RemoveSigningCertificate')) {
            # SAML token-signing certificates. Graph identifies the active one by SHA-1 thumbprint
            # (preferredTokenSigningKeyThumbprint) while keyCredentials only carry the public key,
            # so derive the thumbprint from the key bytes rather than trusting customKeyIdentifier,
            # which is SHA-256 on portal-issued certs.
            if ($Type -ne 'servicePrincipals') { throw 'Token signing certificates exist only on service principals.' }
            $GetSigning = {
                $Sp = New-GraphGetRequest -Uri "$Uri`?`$select=displayName,preferredTokenSigningKeyThumbprint,keyCredentials,passwordCredentials" -tenantid $TenantFilter -AsApp $true
                $Preferred = "$($Sp.preferredTokenSigningKeyThumbprint)".ToUpperInvariant()
                $Certs = foreach ($Cred in @($Sp.keyCredentials | Where-Object { $_.usage -eq 'Verify' -and $_.key })) {
                    $Thumb = ([System.BitConverter]::ToString([System.Security.Cryptography.SHA1]::HashData([System.Convert]::FromBase64String($Cred.key))) -replace '-', '')
                    [PSCustomObject]@{
                        keyId               = $Cred.keyId
                        customKeyIdentifier = $Cred.customKeyIdentifier
                        displayName         = $Cred.displayName
                        thumbprint          = $Thumb
                        startDateTime       = $Cred.startDateTime
                        endDateTime         = $Cred.endDateTime
                        preferred           = $Thumb -eq $Preferred
                    }
                }
                [PSCustomObject]@{ DisplayName = $Sp.displayName; Preferred = $Preferred; Certificates = @($Certs); Sp = $Sp }
            }
            if ($Action -eq 'ListSigningCertificates') {
                $Signing = & $GetSigning
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = @{ Results = @($Signing.Certificates | Select-Object -ExcludeProperty customKeyIdentifier); Metadata = @{ Preferred = $Signing.Preferred } }
                    })
            } elseif ($Action -eq 'AddSigningCertificate') {
                # Entra generates the key pair server-side and adds it alongside the current one.
                # Nothing signs with it until SetPreferredSigningKey.
                # The display name becomes the immutable certificate subject and relying parties may
                # show it, so default to Entra's own subject rather than branding it.
                $DisplayName = "$($Request.Body.DisplayName)".Trim()
                if (-not $DisplayName) { $DisplayName = 'Microsoft Azure Federated SSO Certificate' }
                if ($DisplayName -notmatch '^CN=') { $DisplayName = "CN=$DisplayName" }
                $EndDateTime = $Request.Body.EndDateTime
                $End = if (-not $EndDateTime) {
                    # Graph defaults to 3 years, which the tenant's app management policy may cap
                    # (asymmetricKeyLifetime). Default to the shorter of the two.
                    $Max = [TimeSpan]::FromDays(3 * 365)
                    try {
                        $Policies = @(New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/defaultAppManagementPolicy' -tenantid $TenantFilter -AsApp $true)
                        $Policies += @(New-GraphGetRequest -Uri "$Uri/appManagementPolicies" -tenantid $TenantFilter -AsApp $true)
                        foreach ($Policy in $Policies) {
                            if ($Policy.isEnabled -eq $false) { continue }
                            $Rules = @($Policy.servicePrincipalRestrictions.keyCredentials) + @($Policy.restrictions.keyCredentials)
                            foreach ($Rule in ($Rules | Where-Object { $_.restrictionType -eq 'asymmetricKeyLifetime' -and $_.state -eq 'enabled' -and $_.maxLifetime })) {
                                $Lifetime = [System.Xml.XmlConvert]::ToTimeSpan($Rule.maxLifetime)
                                if ($Lifetime -lt $Max) { $Max = $Lifetime }
                            }
                        }
                    } catch {
                        Write-Information "Could not read app management policies for $TenantFilter, using the 3 year default: $($_.Exception.Message)"
                    }
                    # A day of slack so the lifetime Graph measures from its own clock stays under the cap.
                    [DateTimeOffset]::UtcNow.Add($Max).AddDays(-1)
                } elseif ("$EndDateTime" -match '^\d+$') {
                    # The date picker posts unix seconds; accept ISO strings too.
                    [DateTimeOffset]::FromUnixTimeSeconds([int64]$EndDateTime)
                } else {
                    [DateTimeOffset]::Parse("$EndDateTime")
                }
                $CertBody = @{ displayName = $DisplayName; endDateTime = $End.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
                $NewCert = New-GraphPOSTRequest -Uri "$Uri/addTokenSigningCertificate" -Body ($CertBody | ConvertTo-Json -Compress) -tenantid $TenantFilter -AsApp $true
                $Results = @{
                    resultText = "Added token signing certificate '$($NewCert.displayName)' (thumbprint $($NewCert.thumbprint), expires $($NewCert.endDateTime)). The current certificate stays active until you set the new one as preferred. Graph can take a minute to list it."
                    state      = 'success'
                    details    = @($NewCert | Select-Object keyId, thumbprint, displayName, startDateTime, endDateTime)
                }
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results.resultText -Sev 'Info'
            } elseif ($Action -eq 'RemoveSigningCertificate') {
                $Thumbprint = "$($Request.Body.Thumbprint.value ?? $Request.Body.Thumbprint)".Trim().ToUpperInvariant()
                if ($Thumbprint -notmatch '^[0-9A-F]{40}$') { throw 'Thumbprint must be the 40-character hex SHA-1 thumbprint of a signing certificate on this service principal.' }
                $Signing = & $GetSigning
                $Target = $Signing.Certificates | Where-Object { $_.thumbprint -eq $Thumbprint } | Select-Object -First 1
                if (-not $Target) { throw "No signing certificate with thumbprint $Thumbprint is registered on '$($Signing.DisplayName)'." }
                if ($Target.preferred) { throw "Certificate $Thumbprint is the preferred signing certificate. Set another certificate as preferred first." }
                # A signing cert is a Verify key, a Sign key and the PFX password that share one
                # customKeyIdentifier. Removing just the Verify key via RemoveKey leaves the private half
                # behind and removePassword 500s on the PFX password, so replace both collections in one
                # PATCH. Graph requires retained entries to carry null key material.
                $DropKeyIds = @($Signing.Sp.keyCredentials | Where-Object { $_.customKeyIdentifier -eq $Target.customKeyIdentifier } | ForEach-Object { $_.keyId })
                $KeepKeys = @($Signing.Sp.keyCredentials | Where-Object { $_.keyId -notin $DropKeyIds } | ForEach-Object { $_ | Select-Object keyId, type, usage, displayName, customKeyIdentifier, startDateTime, endDateTime, @{ n = 'key'; e = { $null } } })
                $KeepPasswords = @($Signing.Sp.passwordCredentials | Where-Object { $_.keyId -notin $DropKeyIds } | ForEach-Object { $_ | Select-Object keyId, displayName, customKeyIdentifier, hint, startDateTime, endDateTime, @{ n = 'secretText'; e = { $null } } })
                # Encode each entry individually so both collections stay JSON arrays at 0, 1 or many
                # (a whole-collection ConvertTo-Json collapses single elements).
                $ToJsonArray = { param($Items) '[' + (@($Items | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress -Depth 5 }) -join ',') + ']' }
                $PatchBody = '{{"keyCredentials":{0},"passwordCredentials":{1}}}' -f (& $ToJsonArray $KeepKeys), (& $ToJsonArray $KeepPasswords)
                $null = New-GraphPOSTRequest -Uri $Uri -Type 'PATCH' -Body $PatchBody -tenantid $TenantFilter -AsApp $true
                $Results = @{
                    resultText = "Removed signing certificate $Thumbprint ($($DropKeyIds.Count) key entries and its PFX password) from '$($Signing.DisplayName)'."
                    state      = 'success'
                }
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results.resultText -Sev 'Info'
            } else {
                $Thumbprint = "$($Request.Body.Thumbprint.value ?? $Request.Body.Thumbprint)".Trim().ToUpperInvariant()
                if ($Thumbprint -notmatch '^[0-9A-F]{40}$') { throw 'Thumbprint must be the 40-character hex SHA-1 thumbprint of a signing certificate on this service principal.' }
                $Signing = & $GetSigning
                if ($Signing.Certificates.thumbprint -notcontains $Thumbprint) { throw "No signing certificate with thumbprint $Thumbprint is registered on '$($Signing.DisplayName)'." }
                $null = New-GraphPOSTRequest -Uri $Uri -Type 'PATCH' -Body (@{ preferredTokenSigningKeyThumbprint = $Thumbprint } | ConvertTo-Json -Compress) -tenantid $TenantFilter -AsApp $true
                $Results = @{
                    resultText = "'$($Signing.DisplayName)' now signs tokens with certificate $Thumbprint. Update the relying party's trust before removing the previous certificate."
                    state      = 'success'
                }
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results.resultText -Sev 'Info'
            }
        } elseif ($Action -eq 'UpdateOwners') {
            $AppName = $Request.Body.DisplayName ?? $Id ?? $AppId
            $OwnerById = @{}
            $BulkRequests = foreach ($Owner in $Owners) {
                $OwnerById[$Owner.Id] = $Owner
                if ($Owner.Adding) {
                    @{
                        id      = $Owner.Id
                        method  = 'POST'
                        url     = "$($Type)$($IdPath)/owners/`$ref"
                        body    = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($Owner.Id)" }
                        headers = @{ 'Content-Type' = 'application/json' }
                    }
                } else {
                    @{
                        id     = $Owner.Id
                        method = 'DELETE'
                        url    = "$($Type)$($IdPath)/owners/$($Owner.Id)/`$ref"
                    }
                }
            }

            $BulkResults = New-GraphBulkRequest -Requests @($BulkRequests) -tenantid $TenantFilter -AsApp $true
            $Failed = 0
            $OwnerResults = foreach ($Result in $BulkResults) {
                $Owner = $OwnerById[[string]$Result.id]
                $Label = $Owner.Label ?? $Result.id
                $Adding = $Owner.Adding
                if ($Result.status -ge 200 -and $Result.status -lt 300) {
                    $Message = if ($Adding) { "Added $Label as owner of '$AppName'" } else { "Removed $Label as owner of '$AppName'" }
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
                    @{ resultText = $Message; state = 'success' }
                } else {
                    $Failed++
                    $ErrorText = @(Get-NormalizedError -message ($Result.body.error.message ?? "Request failed with status $($Result.status)"))[0]
                    $Message = if ($Adding) { "Failed to add $Label as owner of '$AppName': $ErrorText" } else { "Failed to remove $Label as owner of '$AppName': $ErrorText" }
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error'
                    @{ resultText = $Message; state = 'error' }
                }
            }

            return ([HttpResponseContext]@{
                    StatusCode = Get-CippBulkStatusCode -Total @($Owners).Count -Failed $Failed
                    Body       = @{ Results = @($OwnerResults) }
                })
        } elseif ($Action -eq 'UpdateAssignments') {
            $Sp = New-GraphGetRequest -Uri "$Uri`?`$select=id,displayName,appRoles,appRoleAssignmentRequired" -tenantid $TenantFilter -AsApp $true
            $AppName = $Sp.displayName
            $ChangeRequired = $null -ne $SetRequired -and $SetRequired -ne [bool]$Sp.appRoleAssignmentRequired
            if (@($AddPrincipals).Count -eq 0 -and @($RemoveAssignments).Count -eq 0 -and -not $ChangeRequired) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ Results = @(@{ resultText = "No changes selected for '$AppName'."; state = 'error' }) }
                    })
            }

            if (@($AddPrincipals).Count -gt 0) {
                # Default Access is only valid on apps that declare no roles for users and groups.
                $UserRoles = @($Sp.appRoles).Where({ $_.isEnabled -and $_.allowedMemberTypes -contains 'User' })
                $RoleError = $null
                if (-not $AppRoleId -and $UserRoles.Count -eq 0) { $AppRoleId = $DefaultAccessRoleId }
                if ($AppRoleId -eq $DefaultAccessRoleId -and $UserRoles.Count -eq 0) {
                    $RoleName = 'Default Access'
                } else {
                    $Role = $UserRoles.Where({ $_.id -eq $AppRoleId }, 'First')[0]
                    if ($Role) {
                        $RoleName = $Role.displayName ?? $Role.value
                    } else {
                        $RoleError = "Select one of the roles '$AppName' offers to users and groups: $(($UserRoles.ForEach({ $_.displayName ?? $_.value })) -join ', ')."
                    }
                }
                if ($RoleError) {
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body       = @{ Results = @(@{ resultText = $RoleError; state = 'error' }) }
                        })
                }
            }

            $AssignmentResults = [System.Collections.Generic.List[object]]::new()
            $Total = 0
            $Failed = 0
            if ($ChangeRequired) {
                $Total++
                $State = if ($SetRequired) { 'on' } else { 'off' }
                try {
                    $null = New-GraphPOSTRequest -Uri $Uri -Type 'PATCH' -Body (ConvertTo-Json -Compress -InputObject @{ appRoleAssignmentRequired = $SetRequired }) -tenantid $TenantFilter -AsApp $true
                    $Message = "Turned 'Assignment required' $State for '$AppName'"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
                    $AssignmentResults.Add(@{ resultText = $Message; state = 'success' })
                } catch {
                    $Failed++
                    $ErrorMessage = Get-CippException -Exception $_
                    $Message = "Failed to turn 'Assignment required' $State for '$AppName': $($ErrorMessage.NormalizedError)"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
                    $AssignmentResults.Add(@{ resultText = $Message; state = 'error' })
                }
            }

            $LabelByRequestId = @{}
            $BulkRequests = @(
                foreach ($Principal in $AddPrincipals) {
                    $LabelByRequestId["add-$($Principal.Id)"] = $Principal.Label
                    @{
                        id      = "add-$($Principal.Id)"
                        method  = 'POST'
                        url     = "servicePrincipals/$($Sp.id)/appRoleAssignedTo"
                        body    = @{ principalId = $Principal.Id; resourceId = $Sp.id; appRoleId = $AppRoleId }
                        headers = @{ 'Content-Type' = 'application/json' }
                    }
                }
                foreach ($Assignment in $RemoveAssignments) {
                    $LabelByRequestId["remove-$($Assignment.Id)"] = $Assignment.Label
                    @{
                        id     = "remove-$($Assignment.Id)"
                        method = 'DELETE'
                        url    = "servicePrincipals/$($Sp.id)/appRoleAssignedTo/$($Assignment.Id)"
                    }
                }
            )
            if ($BulkRequests.Count -gt 0) {
                $Total += $BulkRequests.Count
                foreach ($Result in (New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter -AsApp $true)) {
                    $RequestId = [string]$Result.id
                    $Label = $LabelByRequestId[$RequestId] ?? $RequestId
                    $Adding = $RequestId.StartsWith('add-')
                    if ($Result.status -ge 200 -and $Result.status -lt 300) {
                        $Message = if ($Adding) { "Assigned $Label to '$AppName' as $RoleName" } else { "Removed assignment $Label from '$AppName'" }
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
                        $AssignmentResults.Add(@{ resultText = $Message; state = 'success' })
                    } else {
                        $Failed++
                        $ErrorText = @(Get-NormalizedError -message ($Result.body.error.message ?? "Request failed with status $($Result.status)"))[0]
                        $Message = if ($Adding) { "Failed to assign $Label to '$AppName': $ErrorText" } else { "Failed to remove assignment $Label from '$AppName': $ErrorText" }
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error'
                        $AssignmentResults.Add(@{ resultText = $Message; state = 'error' })
                    }
                }
            }

            return ([HttpResponseContext]@{
                    StatusCode = Get-CippBulkStatusCode -Total $Total -Failed $Failed
                    Body       = @{ Results = @($AssignmentResults) }
                })
        } elseif ($Action -eq 'Hide' -or $Action -eq 'Show') {
            # MyApps portal visibility is stored as the 'HideApp' string in the service
            # principal 'tags' collection. tags is a replace-collection on PATCH, so read the
            # current tags and add/remove only HideApp to avoid clobbering the other tags
            # (e.g. WindowsAzureActiveDirectoryIntegratedApp, which marks the app as SSO-integrated).
            $Hidden = $Action -eq 'Hide'
            $CurrentObject = New-GraphGetRequest -Uri $Uri -tenantid $TenantFilter -AsApp $true
            # Rebuild the collection in a single @() subexpression (no in-place array growth):
            # keep every tag except HideApp, then append HideApp only when hiding.
            $Tags = @(
                $CurrentObject.tags | Where-Object { $_ -ne 'HideApp' }
                if ($Hidden) { 'HideApp' }
            )
            # Encode each tag individually and wrap in brackets so tags is always a JSON array:
            # a whole-collection ConvertTo-Json collapses a single-element array to a scalar (Graph
            # rejects it) and emits nothing for an empty array. This handles 0, 1 and many tags.
            $TagsJson = '[' + (($Tags | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress }) -join ',') + ']'
            $PatchBody = '{{"tags":{0}}}' -f $TagsJson
            $null = New-GraphPOSTRequest -Uri $Uri -Type 'PATCH' -Body $PatchBody -tenantid $TenantFilter -AsApp $true

            $Results = @{
                resultText = if ($Hidden) {
                    "Hid '$($CurrentObject.displayName)' from the MyApps portal"
                } else {
                    "Made '$($CurrentObject.displayName)' visible in the MyApps portal"
                }
                state      = 'success'
            }
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results.resultText -Sev 'Info'
        } else {
            # Handle regular actions (Update, Upsert, Delete)
            $null = New-GraphPOSTRequest @PostParams -tenantid $TenantFilter -AsApp $true
            $Results = @{
                resultText = "Successfully executed $Action on $Type with Id: $Id"
                state      = 'success'
            }
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results.resultText -Sev 'Info'
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Results = $Results }
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = @{
            resultText = "Failed to execute $Action on $Type with Id: $Id. Error: $($ErrorMessage.NormalizedError)"
            state      = 'error'
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results.resultText -Sev 'Error' -LogData $ErrorMessage

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = @($Results) }
            })
    }
}
