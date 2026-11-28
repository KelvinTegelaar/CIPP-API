function Invoke-ExecManagedBaseline {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Baselines.ReadWrite
    .DESCRIPTION
        Adds a baseline CyberDrain publishes through the Managed Baselines integration, or brings a managed baseline up to CyberDrain's current version. Action is Import (with the published baseline's id), Align or Merge (with the baseline's GUID). Align replaces every standard and the stage layout with CyberDrain's. Merge overwrites the standards both sides have, keeps the others, and adds the CyberDrain-only standards whose keys are listed in Add. Preview returns what Align or Merge would change without writing anything.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Action = "$($Request.Body.Action)"
    try {
        $User = $(try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { $null })
        $Placeholder = [PSCustomObject]@{ label = 'Exported Template'; value = 'Exported Template'; type = 'Tenant' }

        if ($Action -eq 'Import') {
            $Id = "$($Request.Body.id)"
            if (-not $Id) { throw [System.ArgumentException]::new('Choose a published baseline to add.') }
            $Package = Invoke-ManagedBaselinesRequest -Path 'PartnerTemplate' -Query @{ id = $Id }
            if (-not $Package.Baseline.templateName) { throw "CyberDrain returned no baseline for '$Id'." }

            $RolloutTable = Get-CippTable -tablename 'BaselineRollouts'
            $Existing = Get-CIPPAzDataTableEntity @RolloutTable -Filter "PartitionKey eq 'rollout'" |
                Where-Object { "$($_.ManagedId)" -eq "$($Package.id)" -and "$($_.ManagedKind)" -ne 'custom' } | Select-Object -First 1
            if ($Existing) {
                throw [System.ArgumentException]::new("'$($Existing.templateName)' was already added from this baseline. Use Align or Merge on the Baselines tab to update it.")
            }

            # Aligning nothing with the package gives the same cleaned stages an Align would write.
            $NewBaseline = [PSCustomObject]@{
                templateName = "$($Package.Baseline.templateName)"
                description  = "$($Package.Baseline.description)"
                assignments  = @($Placeholder)
                stages       = @()
            }
            $Plan = Merge-CIPPManagedBaseline -Local $NewBaseline -Remote $Package.Baseline -Mode 'align' -Definitions @(Get-CIPPBaselineDefinition)
            $Saved = Import-CIPPManagedBaseline -Package $Package -Baseline $Plan.Payload -Kind 'template' -User $User

            $Message = "Added '$($NewBaseline.templateName)' with $(@($Plan.Changes.added).Count) standards. Assign it to tenants in the editor - it arrives assigned to the 'Exported Template' placeholder."
            if (@($Saved.Failures).Count -gt 0) { $Message = "$Message Templates that could not be written: $($Saved.Failures -join '; ')." }
            Write-LogMessage -headers $Request.Headers -API $APIName -message "Added managed baseline $($NewBaseline.templateName) ($($Saved.GUID)), CyberDrain version $($Package.version)." -Sev 'Info'
            $Results = [PSCustomObject]@{ Results = $Message; Metadata = @{ id = $Saved.GUID } }
        } elseif ($Action -in @('Align', 'Merge')) {
            $Local = Get-CIPPBaseline -ID $Request.Body.GUID | Select-Object -First 1
            if (-not $Local) {
                throw [System.Management.Automation.ItemNotFoundException]::new("Baseline '$($Request.Body.GUID)' was not found.")
            }
            if (-not $Local.isManaged) {
                throw [System.ArgumentException]::new("'$($Local.templateName)' is not managed by CyberDrain.")
            }
            $OutOfScope = @(Get-CIPPBaselineOutOfScopeAssignment -Assignments $Local.assignments | Select-Object -Unique)
            if ($OutOfScope.Count -gt 0) {
                throw [System.UnauthorizedAccessException]::new("Your role can't update this baseline, because it is assigned to tenants outside your access: $($OutOfScope -join ', ').")
            }

            $Kind = 'template'
            $Package = $null
            if ("$($Local.managedKind)" -eq 'custom') {
                $Kind = 'custom'
                $Package = (Invoke-ManagedBaselinesRequest -Path 'PartnerRequest' -Query @{ requestId = "$($Local.managedRequestId)" }).package
            } else {
                $Package = Invoke-ManagedBaselinesRequest -Path 'PartnerTemplate' -Query @{ id = "$($Local.managedId)" }
            }
            if (-not $Package.Baseline) { throw "CyberDrain returned no baseline for '$($Local.templateName)'." }

            $Ticked = @($Request.Body.Add | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { $_ })
            $Plan = Merge-CIPPManagedBaseline -Local $Local -Remote $Package.Baseline -Mode $Action.ToLower() -Add $Ticked -Definitions @(Get-CIPPBaselineDefinition)
            # Align writes every template in the package; Merge only the ones its standards point at.
            $Templates = @(foreach ($Reference in @($Package.Baseline.referencedTemplates)) {
                    if (-not $Reference.guid) { continue }
                    if ($Action -eq 'Align' -or @($Plan.TemplateIds).Where({ "$($Reference.guid)" -like "$_*" }, 'First').Count -gt 0) {
                        "$($Reference.displayName ?? $Reference.guid)"
                    }
                })

            if ($Request.Body.Preview -eq $true) {
                $Results = [PSCustomObject]@{
                    Results  = "CyberDrain's version $($Package.version) of '$($Local.templateName)'."
                    Metadata = [PSCustomObject]@{
                        action         = $Action
                        baselineName   = $Local.templateName
                        currentVersion = "$($Local.managedVersion)"
                        newVersion     = "$($Package.version)"
                        overwritten    = @($Plan.Changes.overwritten)
                        unchanged      = $Plan.Changes.unchanged
                        removed        = @($Plan.Changes.removed)
                        kept           = @($Plan.Changes.kept)
                        added          = @($Plan.Changes.added)
                        available      = @($Plan.Changes.available)
                        stages         = $Plan.Changes.stages
                        templates      = $Templates
                    }
                }
            } else {
                $ImportParams = @{ Package = $Package; Baseline = $Plan.Payload; Kind = $Kind; RequestId = $Local.managedRequestId; User = $User }
                if ($Action -eq 'Merge') { $ImportParams.TemplateIds = @($Plan.TemplateIds) }
                $Saved = Import-CIPPManagedBaseline @ImportParams

                $Counts = '{0} overwritten, {1} added' -f @($Plan.Changes.overwritten).Count, @($Plan.Changes.added).Count
                if ($Action -eq 'Align') {
                    $Message = "Aligned '$($Local.templateName)' with CyberDrain's version $($Package.version): $Counts, $(@($Plan.Changes.removed).Count) removed."
                } else {
                    $Message = "Merged CyberDrain's version $($Package.version) into '$($Local.templateName)': $Counts, $(@($Plan.Changes.kept).Count) of your own kept."
                }
                if (@($Saved.Failures).Count -gt 0) { $Message = "$Message Templates that could not be written: $($Saved.Failures -join '; ')." }
                Write-LogMessage -headers $Request.Headers -API $APIName -message "$Message ($($Saved.GUID))" -Sev 'Info'
                $Results = [PSCustomObject]@{ Results = $Message; Metadata = @{ id = $Saved.GUID } }
            }
        } else {
            throw [System.ArgumentException]::new("Unknown action '$Action'. Use Import, Align or Merge.")
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Managed baseline $Action failed: $($_.Exception.Message)" -Sev 'Error'
        $Results = [PSCustomObject]@{ Results = "Managed baseline $Action failed: $($_.Exception.Message)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
