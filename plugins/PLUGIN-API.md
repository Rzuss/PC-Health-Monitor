# PC-Health-Monitor Plugin API Contract

Plugins are `.psm1` files placed in the `plugins/` directory next to `PC-Health-Monitor.ps1`.
Each plugin is auto-discovered and loaded at startup. A broken plugin will be skipped — it will never crash the host application.

---

## Required Exported Functions

Every plugin **must** export exactly these three functions:

---

### 1. `Get-PluginManifest`

Returns a hashtable with plugin metadata. Called once at load time.

```powershell
function Get-PluginManifest {
    return @{
        Name        = 'My Plugin'       # Internal identifier
        TabName     = '🔌 My Plugin'    # Text shown on the tab (emoji allowed)
        Version     = '1.0'
        Author      = 'Your Name'
        Description = 'What this plugin monitors'
    }
}
```

---

### 2. `Initialize-Plugin`

Builds the plugin's UI inside the provided panel. Called once when the tab is created.

```powershell
function Initialize-Plugin {
    param(
        [System.Windows.Forms.Panel]$ParentPanel,
        [hashtable]$Colors
    )
    # Create controls and add them to $ParentPanel.
    # Use $Colors for all styling — do NOT hardcode color values.
    # Available keys: BgBase, BgCard, BgCard2, BgCard3, Blue, BlueGlow,
    #   Purple, PurpleGlow, Green, Yellow, Red, Orange, Text, SubText,
    #   Dim, White, DarkRed, DarkGreen, Border
}
```

**Rules:**
- All UI controls must be added to `$ParentPanel`.
- Use `$Colors` (the global `$C` palette) for every color — hardcoded values are forbidden.
- Store references to controls you need to update in module-scoped variables (`$Script:MyControl`).

---

### 3. `Refresh-Plugin`

Updates the plugin's displayed data. Called by the main timer approximately every 6 seconds **only when the plugin's tab is the active tab**.

```powershell
function Refresh-Plugin {
    param(
        [System.Windows.Forms.Panel]$DataPanel
    )
    # Query data and update your stored controls.
    # Do NOT call Write-Log here — this runs on the main thread
    # but should be kept lightweight (< 200 ms).
}
```

**Rules:**
- Keep execution fast. Long-running queries must use a Runspace.
- `Write-Log` is available (main thread), but avoid noisy per-tick logging.
- `$DataPanel` is the same panel passed to `Initialize-Plugin`.

---

## Export Declaration

End every plugin file with:

```powershell
Export-ModuleMember -Function Get-PluginManifest, Initialize-Plugin, Refresh-Plugin
```

---

## Naming Convention

Use a `$Script:` prefix for all module-level state to avoid polluting the global namespace:

```powershell
$Script:MyGrid   = $null
$Script:MyColors = $null
```

---

## Example Skeleton

```powershell
# my-plugin.psm1

$Script:MyGrid   = $null
$Script:MyColors = $null

function Get-PluginManifest {
    return @{
        Name        = 'My Plugin'
        TabName     = '🔌 My Plugin'
        Version     = '1.0'
        Author      = 'Your Name'
        Description = 'Short description'
    }
}

function Initialize-Plugin {
    param(
        [System.Windows.Forms.Panel]$ParentPanel,
        [hashtable]$Colors
    )
    $Script:MyColors = $Colors
    # build UI, add to $ParentPanel
}

function Refresh-Plugin {
    param(
        [System.Windows.Forms.Panel]$DataPanel
    )
    # update $Script:MyGrid or other stored controls
}

Export-ModuleMember -Function Get-PluginManifest, Initialize-Plugin, Refresh-Plugin
```
