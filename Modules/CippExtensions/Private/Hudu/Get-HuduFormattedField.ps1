function Get-HuduFormattedField ($Title, $Value) {
    return @"
<div class="card__item">
    <div class="card__item-slot">
        $Title
    </div>
    <div class="card__item-slot">
        $Value
    </div>
</div>
"@
}

