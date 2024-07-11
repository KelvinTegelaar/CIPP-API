function Invoke-CIPPStandardDisableSelfServiceLicenses {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    DisableSelfServiceLicenses
    .CAT
    Entra (AAD) Standards
    .TAG
    "mediumimpact"
    .HELPTEXT
    This standard disables all self service licenses and enables all exclusions
    .ADDEDCOMPONENT
    .LABEL
    Disable Self Service Licensing
    .IMPACT
    Medium Impact
    .POWERSHELLEQUIVALENT
    Update-MSCommerceProductPolicy -PolicyId AllowSelfServicePurchase -ProductId {productId} -Value "Disabled"
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    This standard disables all self service licenses and enables all exclusions
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>

    param($Tenant, $Settings)

    #Write-LogMessage -API 'Standards' -tenant $tenant -message 'Self Service Licenses cannot be disabled' -sev Error
    try {
        $selfServiceItems = (New-GraphGETRequest -scope "aeb86249-8ea3-49e2-900b-54cc8e308f85/.default" -uri "https://licensing.m365.microsoft.com/v1.0/policies/AllowSelfServicePurchase/products" -tenantid $Tenant).items
        #$selfServiceItems = (Invoke-RestMethod -Method GET -Uri "https://licensing.m365.microsoft.com/v1.0/policies/AllowSelfServicePurchase/products" -Headers $header).items
    } catch {
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to retrieve self service products: $($_.Exception.Message)" -sev Error
        throw "Failed to retrieve self service products: $($_.Exception.Message)"
    }

    if ($settings.remediate) {
        if ($settings.exclusions -like "*;*") {
            $exclusions = $settings.Exclusions -split(';')
        } else {
            $exclusions = $settings.Exclusions -split(',')
        }

        $selfServiceItems | ForEach-Object {
            $body = $null

            if ($_.policyValue -eq "Enabled" -AND ($_.productId -in $exclusions)) {
                # Self service is enabled on product and productId is in exclusions, skip
            }
            if ($_.policyValue -eq "Disabled" -AND ($_.productId -in $exclusions)) {
                # Self service is disabled on product and productId is in exclusions, enable
                $body = '{ "policyValue": "Enabled" }'
            }
            if ($_.policyValue -eq "Enabled" -AND ($_.productId -notin $exclusions)) {
                # Self service is enabled on product and productId is NOT in exclusions, disable
                $body = '{ "policyValue": "Disabled" }'
            }
            if ($_.policyValue -eq "Disabled" -AND ($_.productId -notin $exclusions)) {
                # Self service is disabled on product and productId is NOT in exclusions, skip
            }

            try {
                if ($body) {
                    $product = $_
                    New-GraphPOSTRequest -scope "aeb86249-8ea3-49e2-900b-54cc8e308f85/.default" -uri "https://licensing.m365.microsoft.com/v1.0/policies/AllowSelfServicePurchase/products/$($product.productId)" -tenantid $Tenant -body $body -type PUT
                }
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set product status for $($product.productId) with body $($body) for reason: $($_.Exception.Message)" -sev Error
                #Write-Error "Failed to disable product $($product.productName):$($_.Exception.Message)"
            }
        }

        if (!$exclusions) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No exclusions set for self-service licenses, disabled all not excluded licenses for self-service.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Exclusions present for self-service licenses, disabled all not excluded licenses for self-service.' -sev Info
        }
    }

    if ($Settings.alert) {
        $selfServiceItemsToAlert = $selfServiceItems | Where-Object { $_.policyValue -eq "Enabled"}
        if (!$selfServiceItemsToAlert) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'All self-service licenses are disabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'One or more self-service licenses are enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        #Add-CIPPBPAField -FieldName '????' -FieldValue "????" -StoreAs bool -Tenant $tenant
    }
}




