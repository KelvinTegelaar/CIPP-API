function Resolve-CIPPCADependencies {

    # Future Use - Not currently used

    <#
    .SYNOPSIS
        Reconcile Conditional Access policy dependencies (named locations, authentication
        contexts, authentication strengths) ONCE across a set of CA policy/template objects.
    .DESCRIPTION
        Used by the per-tenant CA batch deployment path (Invoke-CIPPCATemplateBatch) so that
        dependencies shared by multiple policies are created/deduplicated a single time. This
        avoids the duplicate named locations, c1-c99 authentication-context id collisions, and
        error 1040 propagation races that occur when many CA policies deploy concurrently and
        each one independently creates the dependencies it references.

        Returns displayName -> id maps that New-CIPPCAPolicy consumes via its -DependencyMap
        parameter. Each policy still resolves its OWN references downstream (using its own
        LocationInfo / AuthContextInfo) so per-template template-ids never collide across policies.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $TenantFilter,
        [object[]]$PolicyObjects,
        $AllNamedLocations = $null,
        $AllAuthStrengthPolicies = $null,
        $AllAuthContexts = $null,
        $Overwrite = $true,
        $Headers,
        $APIName = 'CA Dependency Reconciliation'
    )

    $AuthStrengthMap = @{}
    $AuthContextMap = @{}
    $LocationMap = @{}
    $NewLocationsCreated = $false

    $PolicyObjects = @($PolicyObjects | Where-Object { $_ })
    if ($PolicyObjects.Count -eq 0) {
        return @{
            AuthStrength        = $AuthStrengthMap
            AuthContexts        = $AuthContextMap
            Locations           = $LocationMap
            NewLocationsCreated = $false
        }
    }

    # ---- Authentication strength policies ----
    $NeedAuthStrength = @($PolicyObjects | Where-Object { $_.GrantControls.authenticationStrength.policyType -in @('custom', 'BuiltIn') })
    if ($NeedAuthStrength.Count -gt 0) {
        if ($null -eq $AllAuthStrengthPolicies) {
            try {
                $AllAuthStrengthPolicies = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/authenticationStrength/policies/' -tenantid $TenantFilter -asApp $true
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                throw "Failed to fetch authentication strength policies: $($ErrorMessage.NormalizedError)"
            }
        }
        foreach ($Policy in $NeedAuthStrength) {
            $Strength = $Policy.GrantControls.authenticationStrength
            $Name = $Strength.displayName
            if (!$Name -or $AuthStrengthMap.ContainsKey($Name)) { continue }
            $ExistingStrength = $AllAuthStrengthPolicies | Where-Object -Property displayName -EQ $Name | Select-Object -First 1
            if ($ExistingStrength) {
                $AuthStrengthMap[$Name] = $ExistingStrength.id
            } else {
                $Body = ConvertTo-Json -InputObject $Strength -Depth 10
                try {
                    $GraphRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/authenticationStrength/policies' -body $Body -Type POST -tenantid $TenantFilter -asApp $true -ScheduleRetry $true
                    $AuthStrengthMap[$Name] = $GraphRequest.id
                    $AllAuthStrengthPolicies = @($AllAuthStrengthPolicies) + @([pscustomobject]@{ id = $GraphRequest.id; displayName = $Name })
                    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Created new Authentication Strength Policy: $Name" -Sev 'Info'
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    throw "Failed to create authentication strength policy '$Name': $($ErrorMessage.NormalizedError)"
                }
            }
        }
    }

    # ---- Authentication context class references ----
    $NeedAuthContext = @($PolicyObjects | Where-Object { $_.AuthContextInfo })
    if ($NeedAuthContext.Count -gt 0) {
        if ($null -eq $AllAuthContexts) {
            try {
                $AllAuthContexts = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/authenticationContextClassReferences' -tenantid $TenantFilter -asApp $true
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                throw "Failed to fetch authentication context class references: $($ErrorMessage.NormalizedError)"
            }
        }
        foreach ($Policy in $NeedAuthContext) {
            foreach ($authContext in $Policy.AuthContextInfo) {
                if (-not $authContext.displayName) { continue }
                $Name = $authContext.displayName
                if ($AuthContextMap.ContainsKey($Name)) { continue }
                $ExistingContext = $AllAuthContexts | Where-Object -Property displayName -EQ $Name | Select-Object -First 1
                if ($ExistingContext) {
                    $AuthContextMap[$Name] = $ExistingContext.id
                } else {
                    # Find the next available ID (c1-c99) across the running set so concurrent
                    # contexts in the same batch never collide on the same id.
                    $UsedIds = @($AllAuthContexts.id)
                    $NewId = $null
                    for ($i = 1; $i -le 99; $i++) {
                        if ("c$i" -notin $UsedIds) { $NewId = "c$i"; break }
                    }
                    if (-not $NewId) {
                        throw "No available authentication context IDs (c1-c99) in tenant $TenantFilter"
                    }
                    $Body = @{
                        id          = $NewId
                        displayName = $Name
                        description = if ($authContext.description) { $authContext.description } else { '' }
                        isAvailable = $true
                    } | ConvertTo-Json -Compress
                    try {
                        $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/authenticationContextClassReferences' -body $Body -Type POST -tenantid $TenantFilter -asApp $true
                        $AuthContextMap[$Name] = $NewId
                        $AllAuthContexts = @($AllAuthContexts) + @([pscustomobject]@{ id = $NewId; displayName = $Name })
                        Write-LogMessage -Tenant $TenantFilter -Headers $Headers -API $APIName -message "Created new Authentication Context: $Name with ID $NewId" -Sev 'Info'
                    } catch {
                        $ErrorMessage = Get-CippException -Exception $_
                        throw "Failed to create authentication context '$Name': $($ErrorMessage.NormalizedError)"
                    }
                }
            }
        }
    }

    # ---- Named locations ----
    $NeedLocations = @($PolicyObjects | Where-Object { $_.LocationInfo })
    if ($NeedLocations.Count -gt 0) {
        if ($null -eq $AllNamedLocations) {
            try {
                $AllNamedLocations = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations?$top=999' -tenantid $TenantFilter -asApp $true
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                throw "Failed to fetch named locations: $($ErrorMessage.NormalizedError)"
            }
        }
        foreach ($Policy in $NeedLocations) {
            foreach ($locations in $Policy.LocationInfo) {
                if (!$locations) { continue }
                foreach ($location in $locations) {
                    if (!$location.displayName) { continue }
                    $Name = $location.displayName
                    if ($LocationMap.ContainsKey($Name)) { continue }
                    $ExistingLocation = @($AllNamedLocations | Where-Object -Property displayName -EQ $Name)
                    $locationExists = $ExistingLocation.Count -gt 0
                    if ($locationExists) {
                        $ExistingLocation = $ExistingLocation[0]
                        if ($Overwrite) {
                            $LocationUpdate = $location | Select-Object * -ExcludeProperty id
                            Remove-ODataProperties -Object $LocationUpdate
                            $Body = ConvertTo-Json -InputObject $LocationUpdate -Depth 10
                            try {
                                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations/$($ExistingLocation.id)" -body $Body -Type PATCH -tenantid $TenantFilter -asApp $true -ScheduleRetry $true
                                Write-LogMessage -Tenant $TenantFilter -Headers $Headers -API $APIName -message "Updated existing Named Location: $Name" -Sev 'Info'
                            } catch {
                                $ErrorMessage = Get-CippException -Exception $_
                                Write-LogMessage -Tenant $TenantFilter -Headers $Headers -API $APIName -message "Named Location '$Name' (id: $($ExistingLocation.id)) could not be updated - it may have been deleted. Will attempt to create it. Error: $($ErrorMessage.NormalizedError)" -Sev 'Warning' -LogData $ErrorMessage
                                $locationExists = $false
                            }
                        }
                        if ($locationExists) {
                            $LocationMap[$Name] = $ExistingLocation.id
                        }
                    }
                    if (-not $locationExists) {
                        if ($location.countriesAndRegions) { $location.countriesAndRegions = @($location.countriesAndRegions) }
                        $LocationBody = $location | Select-Object * -ExcludeProperty id
                        Remove-ODataProperties -Object $LocationBody
                        $Body = ConvertTo-Json -InputObject $LocationBody
                        try {
                            $GraphRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -body $Body -Type POST -tenantid $TenantFilter -asApp $true
                            Write-Information "Created named location with ID: $($GraphRequest.id)"
                            # Wait for location to be available before any policy references it
                            $retryCount = 0
                            $MaxRetryCount = 5
                            $LocationRequest = $null
                            do {
                                Start-Sleep -Seconds 3
                                try {
                                    $LocationRequest = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations/$($GraphRequest.id)" -tenantid $TenantFilter -asApp $true -ErrorAction Stop
                                } catch {
                                    Write-Information 'Location not yet available, will retry...'
                                }
                                $retryCount++
                            } while ((!$LocationRequest -or !$LocationRequest.id) -and ($retryCount -lt $MaxRetryCount))

                            if (!$LocationRequest -or !$LocationRequest.id) {
                                Write-Warning "Location $Name created but could not verify availability after $MaxRetryCount attempts. Proceeding anyway."
                            }
                            $NewLocationsCreated = $true
                            $LocationMap[$Name] = $GraphRequest.id
                            $AllNamedLocations = @($AllNamedLocations) + @([pscustomobject]@{ id = $GraphRequest.id; displayName = $Name })
                            Write-LogMessage -Tenant $TenantFilter -Headers $Headers -API $APIName -message "Created new Named Location: $Name" -Sev 'Info'
                        } catch {
                            $ErrorMessage = Get-CippException -Exception $_
                            throw "Failed to create named location $Name : $($ErrorMessage.NormalizedError)"
                        }
                    }
                }
            }
        }
    }

    return @{
        AuthStrength        = $AuthStrengthMap
        AuthContexts        = $AuthContextMap
        Locations           = $LocationMap
        NewLocationsCreated = $NewLocationsCreated
    }
}
