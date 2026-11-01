function Set-CIPPEnrollmentRestriction {
    <#
    .SYNOPSIS
        Creates or updates an enrollment (device type) restriction, then sets its priority and
        assignment.
    .DESCRIPTION
        Writes one singlePlatformRestriction object per Graph platform type the platform needs
        (two for Android). Objects are matched by -ConfigurationIds when editing a known
        restriction, otherwise by display name and platform type; a match is patched and a
        missing type is created, so an Android restriction missing one half is completed.

        Priority (from the settings) is applied to newly created objects only, unless
        -PriorityMode Always, which also moves existing objects - used when an operator edits a
        restriction's priority by hand. Priority is relative to the tenant's other restrictions
        on the same platform type, so templates only set it at creation, and a priority past the
        end of that platform's list places the restriction last.

        Assignment goes through Set-CIPPAssignedPolicy, the same path Intune policies use, so
        AssignTo and customGroup (names, wildcards allowed) or -GroupIds behave identically. A
        restriction with a named target owns its assignment and is replaced to exactly that set;
        'On' (do not assign) leaves the assignment as it is.

        -CreateGroups creates the customGroup names no tenant group matches with New-CIPPGroup,
        from the group template of that name when there is one and otherwise as a security group,
        before any restriction object is written. When it creates one, the restriction is assigned by id, since a new group may not
        be listed by name yet. A wildcard name cannot be created and is left to match what exists.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        $TenantFilter,
        [Parameter(Mandatory = $true)]
        $Settings,
        [string[]]$ConfigurationIds,
        [string[]]$GroupIds,
        [ValidateSet('OnCreate', 'Always')]
        [string]$PriorityMode = 'OnCreate',
        [switch]$CreateGroups,
        $Headers,
        $APIName = 'Set Enrollment Restriction'
    )

    $DisplayName = "$($Settings.displayName)"
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { throw 'A restriction name is required.' }
    $Bodies = New-CIPPEnrollmentRestrictionBody -Settings $Settings
    $AssignTarget = Get-CIPPIntuneAssignTarget -AssignTo $Settings.AssignTo
    $BaseUri = 'https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations'

    try {
        $HasGroupIds = $GroupIds -and @($GroupIds).Count -gt 0
        if ($CreateGroups -and $AssignTarget.AssignTo -eq 'customGroup' -and -not $HasGroupIds) {
            # Names match as Set-CIPPAssignedPolicy matches them: -like, with brackets taken literally.
            $TenantGroups = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$select=id,displayName&$top=999' -tenantid $TenantFilter)
            $ResolvedIds = [System.Collections.Generic.List[string]]::new()
            $CreatedAny = $false
            $GroupTemplates = $null
            foreach ($Name in @("$($Settings.customGroup)".Split(',').Trim() | Where-Object { $_ })) {
                $Pattern = $Name -replace '\[', '`[' -replace '\]', '`]'
                $Matched = @($TenantGroups | Where-Object { "$($_.displayName)" -like $Pattern })
                if ($Matched.Count -gt 0) {
                    $Matched | ForEach-Object { $ResolvedIds.Add("$($_.id)") }
                } elseif ($Name -notmatch '[*?]' -and $PSCmdlet.ShouldProcess($Name, 'Create group')) {
                    # A group template with the name is used when there is one, else a security group.
                    if ($null -eq $GroupTemplates) {
                        $TemplatesTable = Get-CippTable -tablename 'templates'
                        $GroupTemplates = @(Get-CIPPAzDataTableEntity @TemplatesTable -Filter "PartitionKey eq 'GroupTemplate'" | ForEach-Object {
                                if ($_.JSON -and (Test-Json -Json $_.JSON -ErrorAction SilentlyContinue)) { $_.JSON | ConvertFrom-Json }
                            })
                    }
                    # One template only: duplicates would make the create body's displayName an array.
                    $GroupObject = @($GroupTemplates | Where-Object -Property displayName -EQ $Name) | Select-Object -First 1
                    if (-not $GroupObject) {
                        $MailNickname = $Name -replace '[^a-zA-Z0-9]', ''
                        $GroupObject = @{
                            groupType       = 'generic'
                            displayName     = $Name
                            username        = $MailNickname.Substring(0, [Math]::Min(64, $MailNickname.Length))
                            securityEnabled = $true
                        }
                    }
                    $NewGroup = New-CIPPGroup -GroupObject $GroupObject -TenantFilter $TenantFilter -APIName $APIName
                    # Never assign an empty id in place of the group.
                    if (-not $NewGroup.Success -or [string]::IsNullOrWhiteSpace($NewGroup.GroupId)) {
                        throw "Failed to create group '$Name'$(if ($NewGroup.Error) { ": $($NewGroup.Error)" })"
                    }
                    $ResolvedIds.Add("$($NewGroup.GroupId)")
                    $CreatedAny = $true
                }
            }
            if ($CreatedAny) { $GroupIds = @($ResolvedIds | Select-Object -Unique) }
        }

        $Existing = @(New-GraphGetRequest -uri "$BaseUri`?`$top=999" -tenantid $TenantFilter | Where-Object { "$($_.'@odata.type')" -match 'deviceEnrollmentPlatformRestrictionConfiguration$' })

        $Created = 0
        $Updated = 0
        foreach ($PlatformType in $Bodies.Keys) {
            $Body = $Bodies[$PlatformType]
            $Match = $(if ($ConfigurationIds) {
                    $Existing | Where-Object { "$($_.id)" -in $ConfigurationIds -and "$($_.platformType)" -eq $PlatformType } | Select-Object -First 1
                } else {
                    $Existing | Where-Object { "$($_.displayName)" -eq $DisplayName -and "$($_.platformType)" -eq $PlatformType } | Select-Object -First 1
                })

            $IsNew = $null -eq $Match
            $Id = $Match.id
            $CurrentPriority = $Match.priority
            if ($IsNew) {
                if ($PSCmdlet.ShouldProcess("$DisplayName ($PlatformType)", 'Create enrollment restriction')) {
                    $New = New-GraphPOSTRequest -uri $BaseUri -tenantid $TenantFilter -type POST -body (ConvertTo-Json -InputObject $Body -Depth 10 -Compress)
                    $Id = $New.id
                    $CurrentPriority = $New.priority
                    $Created++
                }
            } else {
                # The platform type is fixed when the object is created.
                $PatchBody = [ordered]@{}
                foreach ($Key in $Body.Keys) { if ($Key -ne 'platformType') { $PatchBody[$Key] = $Body[$Key] } }
                if ($PSCmdlet.ShouldProcess("$DisplayName ($PlatformType)", 'Update enrollment restriction')) {
                    $null = New-GraphPOSTRequest -uri "$BaseUri/$Id" -tenantid $TenantFilter -type PATCH -body (ConvertTo-Json -InputObject $PatchBody -Depth 10 -Compress)
                    $Updated++
                }
            }
            if (-not $Id) { continue }

            # Intune numbers restrictions from 1 within each platform type and puts a new one last.
            # setPriority fails for the position an object already holds or one past the end of its
            # platform's list, so the target is capped at the list length and skipped when already met.
            if ($null -ne $Settings.priority -and ($IsNew -or $PriorityMode -eq 'Always')) {
                $PlatformCount = @($Existing | Where-Object { "$($_.platformType)" -eq $PlatformType }).Count + $(if ($IsNew) { 1 } else { 0 })
                $TargetPriority = [Math]::Min([int]$Settings.priority, $PlatformCount)
                if ($null -eq $CurrentPriority) { $CurrentPriority = $PlatformCount }
                if ("$CurrentPriority" -ne "$TargetPriority" -and $PSCmdlet.ShouldProcess("$DisplayName ($PlatformType)", "Set priority $TargetPriority")) {
                    $null = New-GraphPOSTRequest -uri "$BaseUri/$Id/setPriority" -tenantid $TenantFilter -type POST -body (@{ priority = $TargetPriority } | ConvertTo-Json -Compress)
                }
            }
            if ($AssignTarget.Managed) {
                $AssignParams = @{
                    GroupName      = $(if ($AssignTarget.AssignTo -eq 'customGroup') { $Settings.customGroup } else { $AssignTarget.AssignTo })
                    PolicyId       = $Id
                    Type           = 'deviceEnrollmentConfigurations'
                    TenantFilter   = $TenantFilter
                    AssignmentMode = 'replace'
                    Headers        = $Headers
                    APIName        = $APIName
                }
                # '@($null).Count' is 1, so test the value before counting it.
                if ($AssignTarget.AssignTo -eq 'customGroup' -and $GroupIds -and @($GroupIds).Count -gt 0) { $AssignParams.GroupIds = @($GroupIds) }
                $null = Set-CIPPAssignedPolicy @AssignParams
            }
        }

        $Verb = $(if ($Created -gt 0 -and $Updated -eq 0) { 'Created' } else { 'Updated' })
        $Result = "$Verb $($Settings.platform) enrollment restriction '$DisplayName' for $TenantFilter"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to set enrollment restriction '$DisplayName' for $($TenantFilter): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        throw $Result
    }
}
