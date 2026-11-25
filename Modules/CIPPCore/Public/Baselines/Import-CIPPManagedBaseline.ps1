function Import-CIPPManagedBaseline {
    <#
    .SYNOPSIS
        Saves a baseline CyberDrain maintains, after bringing in the templates it refers to.
    .DESCRIPTION
        The one path every managed write takes: adding a published baseline, Align, Merge and
        saving a delivered custom baseline from the editor. They differ only in the payload they
        hand over. The package's templates go through the unchanged Import-CommunityTemplate, so
        the ids the baseline's standards point at survive, and are always overwritten: a managed
        template follows CyberDrain's version.
    .OUTPUTS
        @{ GUID; DeltaCount; Templates = <number written>; Failures = <string[]> }
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)]$Baseline,
        [ValidateSet('template', 'custom')][string]$Kind = 'template',
        $RequestId,
        $User,
        # Only the templates with these ids are written; omitted means every template in the package.
        [string[]]$TemplateIds
    )

    $Failures = [System.Collections.Generic.List[string]]::new()
    $Written = 0
    foreach ($Template in @($Package.Templates)) {
        if (-not $Template.RowKey) { continue }
        if ($PSBoundParameters.ContainsKey('TemplateIds') -and
            @($TemplateIds).Where({ "$($Template.RowKey)" -like "$_*" -or "$($Template.GUID)" -eq $_ }, 'First').Count -eq 0) { continue }
        try {
            $null = Import-CommunityTemplate -Template $Template -SHA ('{0}@{1}' -f $Package.id, $Package.version) -Source 'CyberDrain Managed Baselines' -Force
            $Written++
        } catch {
            $Failures.Add("$($Template.RowKey): $($_.Exception.Message)")
        }
    }

    $Managed = @{ Id = "$($Package.id)"; Version = "$($Package.version)"; Kind = $Kind }
    if ($RequestId) { $Managed.RequestId = "$RequestId" }
    $Saved = New-CIPPBaseline -Baseline $Baseline -User ("$User" ? "$User" : 'CyberDrain Managed Baselines') -Managed $Managed

    @{ GUID = $Saved.GUID; DeltaCount = $Saved.DeltaCount; Templates = $Written; Failures = @($Failures) }
}
