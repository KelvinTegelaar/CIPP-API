function Get-HuduFormattedBlock ($Heading, $Body) {
    return @"
<div class="nasa__block" style="margin-bottom: 20px;">
    <header class='nasa__block-header' style="padding-top: 15px;">
            <h1>$Heading</h1>
        </header>
        <div style="padding-left: 15px; padding-right: 15px; padding-bottom: 15px;">
        $Body
    </div>
</div>
"@
}
