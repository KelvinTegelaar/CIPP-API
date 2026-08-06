function Get-CIPPIntuneCompareExclusions {
    <#
    .SYNOPSIS
        The property names Compare-CIPPIntuneObject never compares.
    .DESCRIPTION
        Single source of truth for the compare's exclusion list. Consumed by
        Compare-CIPPIntuneObject itself AND by the baseline engine's hard-gap pass -
        a hard 'expected false/0 vs empty current' check must never resurrect a
        property the compare deliberately ignores (read-only server state like
        qualityUpdatesWillBeRolledBack, sync metadata, identifiers).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        # App protection templates store apps[] and deployedAppCount, but deployment
        # strips apps and the policy read-back never returns either. Scoped because
        # Device configs carry legitimate nested 'apps' (e.g. kiosk profiles).
        [switch]$AppProtection
    )

    $Exclusions = @(
        'id',
        'createdDateTime',
        'lastModifiedDateTime',
        'supportsScopeTags',
        'modifiedDateTime',
        'version',
        'roleScopeTagIds',
        'settingCount',
        'creationSource',
        'priorityMetaData'
        'featureUpdatesWillBeRolledBack',
        'qualityUpdatesWillBeRolledBack',
        'qualityUpdatesPauseStartDate',
        'featureUpdatesPauseStartDate'
        'wslDistributions',
        'lastSuccessfulSyncDateTime',
        'tenantFilter',
        'agents',
        'isSynced'
        'locationInfo',
        'templateId',
        'source',
        'package',
        'assignments'
    )
    if ($AppProtection) {
        $Exclusions = $Exclusions + @('apps', 'deployedAppCount')
    }
    $Exclusions
}
