function Merge-CippStandards {
    param(
        [Parameter(Mandatory = $true)][object]$Existing,
        [Parameter(Mandatory = $true)][object]$New,
        [Parameter(Mandatory = $true)][string]$StandardName
    )

    # If $Existing or $New is $null/empty, just return the other.
    if (-not $Existing) { return $New }
    if (-not $New) { return $Existing }

    # If the standard name ends with 'Template', we treat them as arrays to merge.
    if ($StandardName -like '*Template') {
        # Combine both tiers, then collapse duplicates that target the same template
        # (same TemplateList.value). Without this, the same Intune/CA template configured
        # in more than one tier (or in more than one standard) for a tenant gets
        # concatenated into a multi-element array, which downstream stringifies into a
        # doubled GUID ("Failed to find template <guid> <guid>") that matches no RowKey.
        #
        # The standards engine already keys each template instance by TemplateList.value,
        # so when this function runs the items share a template GUID and should resolve to
        # a single deployment. Items without a TemplateList.value can't be keyed, so they
        # are always kept (preserves the additive behaviour for those).
        $Combined = @($Existing) + @($New)

        $Deduped = [System.Collections.Generic.List[object]]::new()
        $SeenValues = [System.Collections.Generic.HashSet[string]]::new()
        # Walk newest-first so the most-specific tier wins for a given template, while
        # Insert(0, ...) keeps the overall ordering stable.
        for ($i = $Combined.Count - 1; $i -ge 0; $i--) {
            $Item = $Combined[$i]
            $TemplateValue = $Item.TemplateList.value
            if ([string]::IsNullOrEmpty($TemplateValue)) {
                $Deduped.Insert(0, $Item)
            } elseif ($SeenValues.Add([string]$TemplateValue)) {
                $Deduped.Insert(0, $Item)
            }
        }

        if ($Deduped.Count -eq 1) { return $Deduped[0] }
        return $Deduped.ToArray()
    } else {
        # Single‐value standard: override the old with the new
        return $New
    }
}
