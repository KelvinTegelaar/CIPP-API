function Get-NinjaOneTitle($Title, $Icon, $TitleLink, $TitleSize, $TitleClass) {
    Return $(if ($TitleSize) { '<' + $TitleSize }else { '<span ' }) + $(if ($TitleClass) { ' class="' + $TitleClass + '"' }) + '>' + $(if ($Icon) { '<i class="' + $Icon + '"></i>&nbsp;&nbsp;' }) + $Title + $(if ($TitleLink) { '&nbsp;&nbsp;<a href="' + $TitleLink + '" target="_blank" class="text-decoration-none"><i class="fas fa-arrow-up-right-from-square fa-2xs" style="color: #337ab7;"></i></a>' }) + $(if ($TitleSize) { "</$TitleSize>" }else { '</span>' })
}

### HTML Formatters ###
# Bar Graph
function Get-NinjaInLineBarGraph ($Data, [string]$Title, [string]$Icon, [string]$TitleLink, [switch]$KeyInLine, [switch]$NoCount, [switch]$NoSort) {
    <# 
    Example: 
    $Data = @(
        @{
            Label = 'Licensed'
            Amount = 3
            Colour = '#55ACBF'
        },
        @{
            Label = 'Unlicensed'
            Amount = 1
            Colour = '#3633B7'
        },
        @{
            Label = 'Guests'
            Amount = 10
            Colour = '#8063BF'
        }
    )
    Get-NinjaInLineBarGraph -Title "Users" -Data $Data -KeyInLine

    #>

    if (!$NoSort) {
        $Data = $Data | Sort-Object Amount -Descending
    }

    $Total = ($Data.Amount | measure-object -sum).sum
    [System.Collections.Generic.List[String]]$OutputHTML = @()

    if ($Title) {
        $OutputHTML.add((Get-NinjaOneTitle -Icon $Icon -Title ($Title + $(if (!$NoCount) { " ($Total)" })) -TitleLink $TitleLink))
    }

    $OutputHTML.add('<div class="pb-3 pt-3 linechart">')

    foreach ($Item in $Data) {
        $OutputHTML.add(@"
        <div style="width: $(($Item.Amount / $Total) * 100)%; background-color: $($Item.Colour);"></div>
"@)

    }

    $OutputHTML.add('</div>')

    if ($KeyInline) {
        $OutputHTML.add('<ul class="unstyled p-3" style="display: flex; justify-content: space-between;">')
    } else {
        $OutputHTML.add('<ul class="unstyled p-3" >')
    }

    foreach ($Item in $Data) {
        $OutputHTML.add(@"
        <li><span class="chart-key" style="background-color: $($Item.Colour);"></span><span > $($Item.Label) ($($Item.Amount))</span></li>
"@)

    }

    $OutputHTML.add('</ul>')

    return $OutputHTML -join ''


}

#### List of Links
function Get-NinjaOneLinks ($Data, $Title, [string]$Icon, [string]$TitleLink, [int]$SmallCols, [int]$MedCols, [int]$LargeCols, [int]$XLCols) {
    <#
$ManagementLinksData = @(
        @{
            Name = 'M365 Admin Portal'
            Link = "https://portal.office.com/Partner/BeginClientSession.aspx?CTID=$($customer.CustomerId)&CSDEST=o365admincenter"
            Icon = 'fas fa-cogs'
        },
        @{
            Name = 'Exchange Admin Portal'
            Link = "https://outlook.office365.com/ecp/?rfr=Admin_o365&exsvurl=1&delegatedOrg=$($Customer.DefaultDomainName)"
            Icon = 'fas fa-mail-bulk'
        },
        @{
            Name = 'Entra Admin'
            Link = "https://aad.portal.azure.com/$($Customer.DefaultDomainName)"
            Icon = 'fas fa-users-cog'
        })

        Get-NinjaOneLinks -Title 'M365 Admin Links' -Data $ManagementLinksData
#>

    [System.Collections.Generic.List[String]]$OutputHTML = @()

    $OutputHTML.add('<div class="card flex-grow-1">')

    if ($Title) {
        $OutputHTML.add('<div class="card-title-box"><div class="card-title">' + $(if ($Icon) { '<i class="' + $Icon + '"></i>&nbsp;&nbsp;' }) + $Title + '</div>')

        if ($TitleLink) {
            $OutputHTML.add('<div class="card-link-box"><a href="' + $TitleLink + '" target="_blank" class="card-link"><i class="fas fa-arrow-up-right-from-square"></i></a></div>')
        }

        $OutputHTML.add('</div>')
    }

    $OutputHTML.add('<div class="card-body">')
    $OutputHTML.add('<ul class="row unstyled">')

    $CSSCols = Get-NinjaOneCSSCol -SmallCols $SmallCols -MedCols $MedCols -LargeCols $LargeCols -XLCols $XLCols

   
    foreach ($Item in $Data) {


        $OutputHTML.add(@"
        <li class="$CSSCols"><a href="$($Item.Link)" target="_blank">$(if ($Item.Icon){"<span><i class=`"$($Item.Icon)`"></i>&nbsp;&nbsp;</span>"})<span style="text-align: center;">$($Item.Name)</span></a></li>
"@)

    }

    $OutputHTML.add('</ul></div></div>')

    return $OutputHTML -join ''

}


function Get-NinjaOneWidgetCard($Title, $Data, [string]$Icon, [string]$TitleLink, [int]$SmallCols, [int]$MedCols, [int]$LargeCols, [int]$XLCols, [Switch]$NoCard) {
    <#
    $Data = @(
        @{
            Value = 20
            Description = 'Users'
            Colour = '#CCCCCC'
            Link = 'https://example.com/users'
        },
        @{
            Value = 42
            Description = 'Devices'
            Colour = '#CCCCCC'
            Link = 'https://example.com/devices'
        }
    )
    
    $HTML = Get-NinjaOneWidgetCard -Title 'Summary Details' -Data $Data -Icon 'fas fa-building' -TitleLink 'http://example.com' -Columns 3

    #>

    $CSSCols = Get-NinjaOneCSSCol -SmallCols $SmallCols -MedCols $MedCols -LargeCols $LargeCols -XLCols $XLCols


    [System.Collections.Generic.List[String]]$OutputHTML = @()
    
    $OutputHTML.add('<div class="row d-flex m-1 justify-content-center align-items-center">')


    foreach ($Item in $Data) {

        $HTML = @"
    <div class="$CSSCols">
    <div class="stat-card">
    <div class="stat-value"><a href="$($Item.Link)" target="_blank"><span style="color: $($Item.Colour);">$($Item.Value)</span></a></div>
    <div class="stat-desc"><a href="$($Item.Link)" target="_blank"><span style="font-size: 18px;"><span style="white-space:nowrap;">$($Item.Description)</span></span></a></div>
        </div>
    </div>
"@

        $OutputHTML.add($HTML)

    }

    $OutputHTML.add('</div>')

    if ($NoCard) {
        return $OutputHTML -join ''
    } else {
        Return Get-NinjaOneCard -Title $Title -Body ($OutputHTML -join '') -Icon $Icon -TitleLink $TitleLink
    }

}

Function Get-NinjaOneCSSCol($SmallCols, $MedCols, $LargeCols, $XLCols) {
    $SmallCSS = "col-sm-$([Math]::Floor(12 / $SmallCols))"
    $MediumCSS = "col-md-$([Math]::Floor(12 / $MedCols))"
    $LargeCSS = "col-lg-$([Math]::Floor(12 / $LargeCols))"
    $XLCSS = "col-xl-$([Math]::Floor(12 / $XLCols))"

    Return "$SmallCSS $MediumCSS $LargeCSS $XLCSS"
}

function Get-NinjaOneCard($Title, $Body, [string]$Icon, [string]$TitleLink, [String]$Classes) {
    <#
    $Info = 'This is the body of a card it is wrapped in a paragraph'

    Get-NinjaOneCard -Title "Tenant Details" -Data $Info
    #>

    [System.Collections.Generic.List[String]]$OutputHTML = @()

    $OutputHTML.add('<div class="card flex-grow-1' + $(if ($classes) { ' ' + $classes }) + '" >')

    if ($Title) {
        $OutputHTML.add('<div class="card-title-box"><div class="card-title" >' + $(if ($Icon) { '<i class="' + $Icon + '"></i>&nbsp;&nbsp;' }) + $Title + '</div>')

        if ($TitleLink) {
            $OutputHTML.add('<div class="card-link-box"><a href="' + $TitleLink + '" target="_blank" class="card-link" ><i class="fas fa-arrow-up-right-from-square" style="color: #337ab7;"></i></a></div>')
        }

        $OutputHTML.add('</div>')
    }

    $OutputHTML.add('<div class="card-body" >')
    $OutputHTML.add('<p class="card-text" >' + $Body + '</p>')
       
    $OutputHTML.add('</div></div>')

    return $OutputHTML -join ''
    
}

function Get-NinjaOneInfoCard($Title, $Data, [string]$Icon, [string]$TitleLink) {
    <#
    $TenantDetailsItems = [PSCustomObject]@{
        'Name' = $Customer.displayName
        'Default Domain' = $Customer.defaultDomainName
        'Tenant ID' = $Customer.customerId
        'Domains' = $customerDomains
        'Admin Users' = ($AdminUsers | ForEach-Object {"$($_.displayname) ($($_.userPrincipalName))"}) -join ', '
        'Creation Date' = $TenantDetails.createdDateTime
    }

    Get-NinjaOneInfoCard -Title "Tenant Details" -Data $TenantDetailsItems
    #>

    [System.Collections.Generic.List[String]]$ItemsHTML = @()

    foreach ($Item in $Data.PSObject.Properties) {
        $ItemsHTML.add('<p ><b >' + $Item.Name + '</b><br />' + $Item.Value + '</p>')
    }

    return Get-NinjaOneCard -Title $Title -Body ($ItemsHTML -join '') -Icon $Icon -TitleLink $TitleLink
       
}

