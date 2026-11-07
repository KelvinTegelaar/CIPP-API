function Get-CippIntuneSettingInstance {
    <#
    .SYNOPSIS
    Internal helper that flattens a Settings Catalog policy's settings into every nested settingInstance.
    #>
    [CmdletBinding()]
    param($Settings)

    $Pending = [System.Collections.Generic.Queue[object]]::new()
    foreach ($Setting in @($Settings)) {
        if ($null -ne $Setting.settingInstance) { $Pending.Enqueue($Setting.settingInstance) }
    }
    while ($Pending.Count -gt 0) {
        $Instance = $Pending.Dequeue()
        $Instance
        $Children = @(
            $Instance.choiceSettingValue.children
            $Instance.groupSettingValue.children
            foreach ($Value in @($Instance.groupSettingCollectionValue)) { $Value.children }
            foreach ($Value in @($Instance.choiceSettingCollectionValue)) { $Value.children }
            foreach ($Value in @($Instance.simpleSettingCollectionValue)) { $Value.children }
        )
        foreach ($Child in $Children) {
            if ($null -ne $Child) { $Pending.Enqueue($Child) }
        }
    }
}
