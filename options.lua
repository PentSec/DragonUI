local addon = select(2, ...);

-- Define the reload dialog
StaticPopupDialogs["DRAGONUI_RELOAD_UI"] = {
    text = "Changing this setting requires a UI reload to apply correctly.",
    button1 = "Reload UI",
    button2 = "Not Now",
    OnAccept = function()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3
};

-- Function to create configuration options (called after DB is ready)
function addon:CreateOptionsTable()
    return {
        name = "DragonUI",
        type = 'group',
        args = {
            --  BOTÓN PARA ACTIVAR EL MODO DE EDICIÓN
            toggle_editor_mode = {
                type = 'execute',
                name = function()
                    -- El nombre del botón cambia dinámicamente y maneja la lógica de estado
                    if addon.EditorMode then
                        local success, isActive = pcall(function()
                            return addon.EditorMode:IsActive()
                        end)
                        if success and isActive then
                            return "|cffFF6347Exit Editor Mode|r"
                        end
                    end
                    return "|cff00FF00Move UI Elements|r"
                end,
                desc = "Unlock UI elements to move them with your mouse. A button will appear to exit this mode.",
                func = function()
                    --  CORRECCIÓN 3: Ocultar el tooltip para que no se quede pegado.
                    GameTooltip:Hide()

                    -- Usar la función de la librería para cerrar su propia ventana.
                    LibStub("AceConfigDialog-3.0"):Close("DragonUI")

                    -- Llama a la función Toggle del editor_mode.lua
                    if addon.EditorMode then
                        addon.EditorMode:Toggle()
                    end
                end,
                -- FORCE button to be enabled initially to avoid AceConfig timing issues
                disabled = false,
                order = 0 -- El orden más bajo para que aparezca primero
            },
            
            -- ✅ KEYBINDING MODE BUTTON
            toggle_keybind_mode = {
                type = 'execute',
                name = function()
                    if LibStub and LibStub("LibKeyBound-1.0", true) and LibStub("LibKeyBound-1.0"):IsShown() then
                        return "|cffFF6347KeyBind Mode Active|r"
                    else
                        return "|cff00FF00KeyBind Mode|r"
                    end
                end,
                desc = "Toggle keybinding mode. Hover over action buttons and press keys to bind them instantly. Press ESC to clear bindings.",
                func = function()
                    GameTooltip:Hide()
                    -- Close DragonUI options window
                    LibStub("AceConfigDialog-3.0"):Close("DragonUI")
                    
                    if addon.KeyBindingModule and LibStub and LibStub("LibKeyBound-1.0", true) then
                        local LibKeyBound = LibStub("LibKeyBound-1.0")
                        LibKeyBound:Toggle()
                    else
                        print("|cFFFF0000[DragonUI]|r KeyBinding module not available")
                    end
                end,
                disabled = function()
                    return not (addon.KeyBindingModule and addon.KeyBindingModule.enabled)
                end,
                order = 0.3
            },
            
            --  SEPARADOR VISUAL
            editor_separator = {
                type = 'header',
                name = ' ', -- Un espacio en blanco actúa como separador
                order = 0.5
            },

            -- NUEVA SECCIÓN: MODULES
            modules = {
                type = 'group',
                name = "Modules",
                desc = "Enable or disable specific DragonUI modules",
                order = 0.6,
                args = {
                    description = {
                        type = 'description',
                        name = "|cffFFD700Module Control|r\n\nEnable or disable specific DragonUI modules. When disabled, the original Blizzard UI will be shown instead.",
                        order = 1
                    },

                    castbars_header = {
                        type = 'header',
                        name = "Cast Bars",
                        order = 10
                    },

                    player_castbar_enabled = {
                        type = 'toggle',
                        name = "Player Castbar",
                        desc = "Enable DragonUI player castbar. When disabled, shows default Blizzard castbar.",
                        get = function()
                            return addon.db.profile.castbar.enabled
                        end,
                        set = function(info, val)
                            addon.db.profile.castbar.enabled = val
                            if addon.RefreshCastbar then
                                addon.RefreshCastbar()
                            end
                        end,
                        order = 11
                    },

                    target_castbar_enabled = {
                        type = 'toggle',
                        name = "Target Castbar",
                        desc = "Enable DragonUI target castbar. When disabled, shows default Blizzard castbar.",
                        get = function()
                            if not addon.db.profile.castbar.target then
                                return true
                            end
                            local value = addon.db.profile.castbar.target.enabled
                            if value == nil then
                                return true
                            end
                            return value == true
                        end,
                        set = function(info, val)
                            if not addon.db.profile.castbar.target then
                                addon.db.profile.castbar.target = {}
                            end
                            addon.db.profile.castbar.target.enabled = val
                            if addon.RefreshTargetCastbar then
                                addon.RefreshTargetCastbar()
                            end
                        end,
                        order = 12
                    },

                    focus_castbar_enabled = {
                        type = 'toggle',
                        name = "Focus Castbar",
                        desc = "Enable DragonUI focus castbar. When disabled, shows default Blizzard castbar.",
                        get = function()
                            return addon.db.profile.castbar.focus.enabled
                        end,
                        set = function(info, value)
                            addon.db.profile.castbar.focus.enabled = value
                            if addon.RefreshFocusCastbar then
                                addon.RefreshFocusCastbar()
                            end
                        end,
                        order = 13
                    },

                    -- Main modules section
                    other_modules_header = {
                        type = 'header',
                        name = "Other Modules",
                        order = 20
                    },

                    -- UNIFIED ACTION BARS SYSTEM
                    actionbars_system_enabled = {
                        type = 'toggle',
                        name = "Action Bars System",
                        desc = "Enable the complete DragonUI action bars system. This controls: Main action bars, vehicle interface, stance/shapeshift bars, pet action bars, multicast bars (totems/possess), button styling, and hide Blizzard elements. When disabled, all action bar related features will use default Blizzard interface.",
                        get = function()
                            -- Check if the unified system is enabled by checking if all components are enabled
                            local modules = addon.db.profile.modules
                            if not modules then
                                return false
                            end

                            return (modules.mainbars and modules.mainbars.enabled) and
                                       (modules.vehicle and modules.vehicle.enabled) and
                                       (modules.stance and modules.stance.enabled) and
                                       (modules.petbar and modules.petbar.enabled) and
                                       (modules.multicast and modules.multicast.enabled) and
                                       (modules.buttons and modules.buttons.enabled) and
                                       (modules.noop and modules.noop.enabled)
                        end,
                        set = function(info, val)
                            if not addon.db.profile.modules then
                                addon.db.profile.modules = {}
                            end
                            -- Initialize all module tables if they don't exist and set their enabled state
                            local moduleNames = {"mainbars", "vehicle", "stance", "petbar", "multicast", "buttons",
                                                 "noop"}
                            for _, moduleName in ipairs(moduleNames) do
                                if not addon.db.profile.modules[moduleName] then
                                    addon.db.profile.modules[moduleName] = {}
                                end
                                addon.db.profile.modules[moduleName].enabled = val
                            end
                            StaticPopup_Show("DRAGONUI_RELOAD_UI")
                        end,
                        order = 21
                    },

                    -- MICRO MENU & BAGS
                    micromenu_enabled = {
                        type = 'toggle',
                        name = "Micro Menu & Bags",
                        desc = "Apply DragonUI micro menu and bags system styling and positioning. Includes character button, spellbook, talents, etc. and bag management. When disabled, these elements will use default Blizzard positioning and styling.",
                        get = function()
                            return addon.db.profile.modules and addon.db.profile.modules.micromenu and
                                       addon.db.profile.modules.micromenu.enabled
                        end,
                        set = function(info, val)
                            if not addon.db.profile.modules then
                                addon.db.profile.modules = {}
                            end
                            if not addon.db.profile.modules.micromenu then
                                addon.db.profile.modules.micromenu = {}
                            end
                            addon.db.profile.modules.micromenu.enabled = val
                            StaticPopup_Show("DRAGONUI_RELOAD_UI")
                        end,
                        order = 22
                    },

                    -- COOLDOWN TIMERS
                    cooldowns_enabled = {
                        type = 'toggle',
                        name = "Cooldown Timers",
                        desc = "Show cooldown timers on action buttons. When disabled, cooldown timers will be hidden and the system will be completely deactivated.",
                        get = function()
                            return addon.db.profile.modules and addon.db.profile.modules.cooldowns and
                                       addon.db.profile.modules.cooldowns.enabled
                        end,
                        set = function(info, val)
                            if not addon.db.profile.modules then
                                addon.db.profile.modules = {}
                            end
                            if not addon.db.profile.modules.cooldowns then
                                addon.db.profile.modules.cooldowns = {}
                            end
                            addon.db.profile.modules.cooldowns.enabled = val
                            if addon.RefreshCooldownSystem then
                                addon.RefreshCooldownSystem()
                            end
                        end,
                        order = 23
                    },

                    -- MINIMAP SYSTEM
                    minimap_enabled = {
                        type = 'toggle',
                        name = "Minimap System",
                        desc = "Enable DragonUI minimap enhancements including custom styling, positioning, tracking icons, and calendar. When disabled, uses default Blizzard minimap appearance and positioning.",
                        get = function()
                            return addon.db.profile.modules and addon.db.profile.modules.minimap and
                                       addon.db.profile.modules.minimap.enabled
                        end,
                        set = function(info, val)
                            if not addon.db.profile.modules then
                                addon.db.profile.modules = {}
                            end
                            if not addon.db.profile.modules.minimap then
                                addon.db.profile.modules.minimap = {}
                            end
                            addon.db.profile.modules.minimap.enabled = val
                            StaticPopup_Show("DRAGONUI_RELOAD_UI")
                        end,
                        order = 24
                    },

                    -- BUFF FRAME SYSTEM
                    buffs_enabled = {
                        type = 'toggle',
                        name = "Buff Frame System",
                        desc = "Enable DragonUI buff frame with custom styling, positioning, and toggle button functionality. When disabled, uses default Blizzard buff frame appearance and positioning.",
                        get = function()
                            return addon.db.profile.modules and addon.db.profile.modules.buffs and
                                       addon.db.profile.modules.buffs.enabled
                        end,
                        set = function(info, val)
                            if not addon.db.profile.modules then
                                addon.db.profile.modules = {}
                            end
                            if not addon.db.profile.modules.buffs then
                                addon.db.profile.modules.buffs = {}
                            end
                            addon.db.profile.modules.buffs.enabled = val
                            if addon.BuffFrameModule then
                                addon.BuffFrameModule:Toggle(val)
                            end
                            StaticPopup_Show("DRAGONUI_RELOAD_UI")
                        end,
                        order = 25
                    },


                }
            },
            actionbars = {
                type = 'group',
                name = "Action Bars",
                order = 1,
                args = {
                    scales = {
                        type = 'group',
                        name = "Action Bar Scales",
                        inline = true,
                        order = 1,
                        args = {
                            scale_actionbar = {
                                type = 'range',
                                name = "Main Bar Scale",
                                desc = "Scale for main action bar",
                                min = 0.5,
                                max = 2.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.mainbars.scale_actionbar
                                end,
                                set = function(info, value)
                                    addon.db.profile.mainbars.scale_actionbar = value
                                    if addon.RefreshMainbars then
                                        addon.RefreshMainbars()
                                    end
                                end,
                                order = 1
                            },
                            scale_rightbar = {
                                type = 'range',
                                name = "Right Bar Scale",
                                desc = "Scale for right action bar (MultiBarRight)",
                                min = 0.5,
                                max = 2.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.mainbars.scale_rightbar
                                end,
                                set = function(info, value)
                                    addon.db.profile.mainbars.scale_rightbar = value
                                    if addon.RefreshMainbars then
                                        addon.RefreshMainbars()
                                    end
                                end,
                                order = 2
                            },
                            scale_leftbar = {
                                type = 'range',
                                name = "Left Bar Scale",
                                desc = "Scale for left action bar (MultiBarLeft)",
                                min = 0.5,
                                max = 2.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.mainbars.scale_leftbar
                                end,
                                set = function(info, value)
                                    addon.db.profile.mainbars.scale_leftbar = value
                                    if addon.RefreshMainbars then
                                        addon.RefreshMainbars()
                                    end
                                end,
                                order = 3
                            },
                            scale_bottomleft = {
                                type = 'range',
                                name = "Bottom Left Bar Scale",
                                desc = "Scale for bottom left action bar (MultiBarBottomLeft)",
                                min = 0.5,
                                max = 2.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.mainbars.scale_bottomleft
                                end,
                                set = function(info, value)
                                    addon.db.profile.mainbars.scale_bottomleft = value
                                    if addon.RefreshMainbars then
                                        addon.RefreshMainbars()
                                    end
                                end,
                                order = 4
                            },
                            scale_bottomright = {
                                type = 'range',
                                name = "Bottom Right Bar Scale",
                                desc = "Scale for bottom right action bar (MultiBarBottomRight)",
                                min = 0.5,
                                max = 2.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.mainbars.scale_bottomright
                                end,
                                set = function(info, value)
                                    addon.db.profile.mainbars.scale_bottomright = value
                                    if addon.RefreshMainbars then
                                        addon.RefreshMainbars()
                                    end
                                end,
                                order = 5
                            },
                            reset_scales = {
                                type = 'execute',
                                name = "Reset All Scales",
                                desc = "Reset all action bar scales to their default values (0.9)",
                                func = function()
                                    -- Reset all scales to default value (0.9)
                                    addon.db.profile.mainbars.scale_actionbar = 0.9
                                    addon.db.profile.mainbars.scale_rightbar = 0.9
                                    addon.db.profile.mainbars.scale_leftbar = 0.9
                                    addon.db.profile.mainbars.scale_bottomleft = 0.9
                                    addon.db.profile.mainbars.scale_bottomright = 0.9
                                    
                                    -- Apply the changes
                                    if addon.RefreshMainbars then
                                        addon.RefreshMainbars()
                                    end
                                    
                                    print("|cFF00FF00[DragonUI]|r All action bar scales reset to default values (0.9)")
                                    
                                    -- Show reload UI dialog
                                    StaticPopup_Show("DRAGONUI_RELOAD_UI")
                                end,
                                order = 6
                            }
                        }
                    },
                    positions = {
                        type = 'group',
                        name = "Action Bar Positions",
                        inline = true,
                        order = 2,
                        args = {
                            editor_mode_desc = {
                                type = 'description',
                                name = "|cffFFD700Tip:|r Use the |cff00FF00Move UI Elements|r button above to reposition action bars with your mouse.",
                                order = 1
                            },
                            left_horizontal = {
                                type = 'toggle',
                                name = "Left Bar Horizontal",
                                desc = "Make the left secondary bar horizontal instead of vertical",
                                get = function()
                                    return addon.db.profile.mainbars.left.horizontal
                                end,
                                set = function(_, value)
                                    addon.db.profile.mainbars.left.horizontal = value
                                    if addon.PositionActionBars then
                                        addon.PositionActionBars()
                                    end
                                end,
                                order = 2
                            },
                            right_horizontal = {
                                type = 'toggle',
                                name = "Right Bar Horizontal",
                                desc = "Make the right secondary bar horizontal instead of vertical",
                                get = function()
                                    return addon.db.profile.mainbars.right.horizontal
                                end,
                                set = function(_, value)
                                    addon.db.profile.mainbars.right.horizontal = value
                                    if addon.PositionActionBars then
                                        addon.PositionActionBars()
                                    end
                                end,
                                order = 3
                            }
                        }
                    },
                    buttons = {
                        type = 'group',
                        name = "Button Appearance",
                        inline = true,
                        order = 2,
                        args = {
                            only_actionbackground = {
                                type = 'toggle',
                                name = "Main Bar Only Background",
                                desc = "If checked, only the main action bar buttons will have a background. If unchecked, all action bar buttons will have a background.",
                                get = function()
                                    return addon.db.profile.buttons.only_actionbackground
                                end,
                                set = function(info, value)
                                    addon.db.profile.buttons.only_actionbackground = value
                                    if addon.RefreshButtons then
                                        addon.RefreshButtons()
                                    end
                                end,
                                order = 1
                            },
                            hide_main_bar_background = {
                                type = 'toggle',
                                name = "Hide Main Bar Background",
                                desc = "Hide the background texture of the main action bar (makes it completely transparent)",
                                get = function()
                                    return addon.db.profile.buttons.hide_main_bar_background
                                end,
                                set = function(info, value)
                                    addon.db.profile.buttons.hide_main_bar_background = value
                                    if addon.RefreshMainbars then
                                        addon.RefreshMainbars()
                                    end
                                end,
                                order = 1.5
                            },
                            count = {
                                type = 'group',
                                name = "Count Text",
                                inline = true,
                                order = 2,
                                args = {
                                    show = {
                                        type = 'toggle',
                                        name = "Show Count",
                                        get = function()
                                            return addon.db.profile.buttons.count.show
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.buttons.count.show = value
                                            if addon.RefreshButtons then
                                                addon.RefreshButtons()
                                            end
                                        end,
                                        order = 1
                                    }
                                }
                            },
                            hotkey = {
                                type = 'group',
                                name = "Hotkey Text",
                                inline = true,
                                order = 4,
                                args = {
                                    show = {
                                        type = 'toggle',
                                        name = "Show Hotkey",
                                        get = function()
                                            return addon.db.profile.buttons.hotkey.show
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.buttons.hotkey.show = value
                                            if addon.RefreshButtons then
                                                addon.RefreshButtons()
                                            end
                                        end,
                                        order = 1
                                    },
                                    range = {
                                        type = 'toggle',
                                        name = "Range Indicator",
                                        desc = "Show small range indicator point on buttons",
                                        get = function()
                                            return addon.db.profile.buttons.hotkey.range
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.buttons.hotkey.range = value
                                            if addon.RefreshButtons then
                                                addon.RefreshButtons()
                                            end
                                        end,
                                        order = 2
                                    }
                                }
                            },
                            macros = {
                                type = 'group',
                                name = "Macro Text",
                                inline = true,
                                order = 5,
                                args = {
                                    show = {
                                        type = 'toggle',
                                        name = "Show Macro Names",
                                        get = function()
                                            return addon.db.profile.buttons.macros.show
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.buttons.macros.show = value
                                            if addon.RefreshButtons then
                                                addon.RefreshButtons()
                                            end
                                        end,
                                        order = 1
                                    }
                                }
                            },
                            pages = {
                                type = 'group',
                                name = "Page Numbers",
                                inline = true,
                                order = 6,
                                args = {
                                    show = {
                                        type = 'toggle',
                                        name = "Show Pages",
                                        get = function()
                                            return addon.db.profile.buttons.pages.show
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.buttons.pages.show = value
                                            StaticPopup_Show("DRAGONUI_RELOAD_UI")
                                        end,
                                        order = 1
                                    }
                                }
                            },
                            cooldown = {

                                type = 'group',
                                name = "Cooldown Text",
                                inline = true,
                                order = 7,
                                args = {
                                    min_duration = {
                                        type = 'range',
                                        name = "Min Duration",
                                        desc = "Minimum duration for text triggering",
                                        min = 1,
                                        max = 10,
                                        step = 1,
                                        get = function()
                                            return addon.db.profile.buttons.cooldown.min_duration
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.buttons.cooldown.min_duration = value
                                            if addon.RefreshCooldowns then
                                                addon.RefreshCooldowns()
                                            end
                                        end,
                                        order = 2
                                    },
                                    color = {
                                        type = 'color',
                                        name = "Text Color",
                                        desc = "Cooldown text color",
                                        get = function()
                                            local c = addon.db.profile.buttons.cooldown.color;
                                            return c[1], c[2], c[3], c[4];
                                        end,
                                        set = function(info, r, g, b, a)
                                            addon.db.profile.buttons.cooldown.color = {r, g, b, a}
                                            if addon.RefreshCooldowns then
                                                addon.RefreshCooldowns()
                                            end
                                        end,
                                        hasAlpha = true,
                                        order = 3
                                    },
                                    font_size = {
                                        type = 'range',
                                        name = "Font Size",
                                        desc = "Size of cooldown text",
                                        min = 8,
                                        max = 24,
                                        step = 1,
                                        get = function()
                                            return addon.db.profile.buttons.cooldown.font_size
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.buttons.cooldown.font_size = value
                                            if addon.RefreshCooldowns then
                                                addon.RefreshCooldowns()
                                            end
                                        end,
                                        order = 4
                                    }
                                }
                            },
                            macros_color = {
                                type = 'color',
                                name = "Macro Text Color",
                                desc = "Color for macro text",
                                get = function()
                                    local c = addon.db.profile.buttons.macros.color;
                                    return c[1], c[2], c[3], c[4];
                                end,
                                set = function(info, r, g, b, a)
                                    addon.db.profile.buttons.macros.color = {r, g, b, a}
                                    if addon.RefreshButtons then
                                        addon.RefreshButtons()
                                    end
                                end,
                                hasAlpha = true,
                                order = 8
                            },
                            hotkey_shadow = {
                                type = 'color',
                                name = "Hotkey Shadow Color",
                                desc = "Shadow color for hotkey text",
                                get = function()
                                    local c = addon.db.profile.buttons.hotkey.shadow;
                                    return c[1], c[2], c[3], c[4];
                                end,
                                set = function(info, r, g, b, a)
                                    addon.db.profile.buttons.hotkey.shadow = {r, g, b, a}
                                    if addon.RefreshButtons then
                                        addon.RefreshButtons()
                                    end
                                end,
                                hasAlpha = true,
                                order = 10
                            },
                            border_color = {
                                type = 'color',
                                name = "Border Color",
                                desc = "Border color for buttons",
                                get = function()
                                    local c = addon.db.profile.buttons.border_color;
                                    return c[1], c[2], c[3], c[4];
                                end,
                                set = function(info, r, g, b, a)
                                    addon.db.profile.buttons.border_color = {r, g, b, a}
                                    if addon.RefreshButtons then
                                        addon.RefreshButtons()
                                    end
                                end,
                                hasAlpha = true,
                                order = 10
                            }
                        }
                    }
                }
            },

            micromenu = {
                type = 'group',
                name = "Micro Menu",
                order = 2,
                args = {
                    grayscale_icons = {
                        type = 'toggle',
                        name = "Gray Scale Icons",
                        desc = "Use grayscale icons instead of colored icons for the micro menu",
                        get = function()
                            return addon.db.profile.micromenu.grayscale_icons
                        end,
                        set = function(info, value)
                            addon.db.profile.micromenu.grayscale_icons = value
                            -- Show reload dialog
                            StaticPopup_Show("DRAGONUI_RELOAD_UI")
                        end,
                        order = 1
                    },
                    separator1 = {
                        type = 'description',
                        name = "",
                        order = 2
                    },
                    current_mode_header = {
                        type = 'header',
                        name = function()
                            return addon.db.profile.micromenu.grayscale_icons and "Grayscale Icons Settings" or
                                       "Normal Icons Settings"
                        end,
                        order = 3
                    },
                    scale_menu = {
                        type = 'range',
                        name = "Menu Scale",
                        desc = function()
                            local mode = addon.db.profile.micromenu.grayscale_icons and "grayscale" or "normal"
                            return "Scale for micromenu (" .. mode .. " icons)"
                        end,
                        min = 0.5,
                        max = 3.0,
                        step = 0.1,
                        get = function()
                            local mode = addon.db.profile.micromenu.grayscale_icons and "grayscale" or "normal"
                            return addon.db.profile.micromenu[mode].scale_menu
                        end,
                        set = function(info, value)
                            local mode = addon.db.profile.micromenu.grayscale_icons and "grayscale" or "normal"
                            addon.db.profile.micromenu[mode].scale_menu = value
                            if addon.RefreshMicromenu then
                                addon.RefreshMicromenu()
                            end
                        end,
                        order = 4
                    },

                    icon_spacing = {
                        type = 'range',
                        name = "Icon Spacing",
                        desc = function()
                            local mode = addon.db.profile.micromenu.grayscale_icons and "grayscale" or "normal"
                            return "Gap between " .. mode .. " icons (pixels)"
                        end,
                        min = 5,
                        max = 40,
                        step = 1,
                        get = function()
                            local mode = addon.db.profile.micromenu.grayscale_icons and "grayscale" or "normal"
                            return addon.db.profile.micromenu[mode].icon_spacing
                        end,
                        set = function(info, value)
                            local mode = addon.db.profile.micromenu.grayscale_icons and "grayscale" or "normal"
                            addon.db.profile.micromenu[mode].icon_spacing = value
                            if addon.RefreshMicromenu then
                                addon.RefreshMicromenu()
                            end
                        end,
                        order = 7
                    },
                    separator2 = {
                        type = 'description',
                        name = "",
                        order = 8
                    },
                    hide_on_vehicle = {
                        type = 'toggle',
                        name = "Hide on Vehicle",
                        desc = "Hide micromenu and bags if you sit on vehicle",
                        get = function()
                            return addon.db.profile.micromenu.hide_on_vehicle
                        end,
                        set = function(info, value)
                            addon.db.profile.micromenu.hide_on_vehicle = value
                            -- Apply vehicle visibility immediately to both micromenu and bags
                            if addon.RefreshMicromenuVehicle then
                                addon.RefreshMicromenuVehicle()
                            end
                            if addon.RefreshBagsVehicle then
                                addon.RefreshBagsVehicle()
                            end
                        end,
                        order = 9
                    },
                                    }
            },

            bags = {
                type = 'group',
                name = "Bags",
                order = 3,
                args = {
                    description = {
                        type = 'description',
                        name = "Configure the position and scale of the bag bar independently from the micro menu.",
                        order = 1
                    },
                    scale = {
                        type = 'range',
                        name = "Scale",
                        desc = "Scale for the bag bar",
                        min = 0.5,
                        max = 2.0,
                        step = 0.1,
                        get = function()
                            return addon.db.profile.bags.scale
                        end,
                        set = function(info, value)
                            addon.db.profile.bags.scale = value
                            if addon.RefreshBagsPosition then
                                addon.RefreshBagsPosition()
                            end
                        end,
                        order = 2
                    }

                }
            },

            xprepbar = {
                type = 'group',
                name = "XP & Rep Bars",
                order = 6,
                args = {
                    bothbar_offset = {
                        type = 'range',
                        name = "Both Bars Offset",
                        desc = "Y offset when XP & reputation bar are shown",
                        min = 0,
                        max = 100,
                        step = 1,
                        get = function()
                            return addon.db.profile.xprepbar.bothbar_offset
                        end,
                        set = function(info, value)
                            addon.db.profile.xprepbar.bothbar_offset = value
                            if addon.RefreshXpRepBarPosition then
                                addon.RefreshXpRepBarPosition()
                            end
                        end,
                        order = 1
                    },
                    singlebar_offset = {
                        type = 'range',
                        name = "Single Bar Offset",
                        desc = "Y offset when XP or reputation bar is shown",
                        min = 0,
                        max = 100,
                        step = 1,
                        get = function()
                            return addon.db.profile.xprepbar.singlebar_offset
                        end,
                        set = function(info, value)
                            addon.db.profile.xprepbar.singlebar_offset = value
                            if addon.RefreshXpRepBarPosition then
                                addon.RefreshXpRepBarPosition()
                            end
                        end,
                        order = 2
                    },
                    nobar_offset = {
                        type = 'range',
                        name = "No Bar Offset",
                        desc = "Y offset when no XP or reputation bar is shown",
                        min = 0,
                        max = 100,
                        step = 1,
                        get = function()
                            return addon.db.profile.xprepbar.nobar_offset
                        end,
                        set = function(info, value)
                            addon.db.profile.xprepbar.nobar_offset = value
                            if addon.RefreshXpRepBarPosition then
                                addon.RefreshXpRepBarPosition()
                            end
                        end,
                        order = 3
                    },
                    repbar_abovexp_offset = {
                        type = 'range',
                        name = "Rep Bar Above XP Offset",
                        desc = "Y offset for reputation bar when XP bar is shown",
                        min = 0,
                        max = 50,
                        step = 1,
                        get = function()
                            return addon.db.profile.xprepbar.repbar_abovexp_offset
                        end,
                        set = function(info, value)
                            addon.db.profile.xprepbar.repbar_abovexp_offset = value
                            if addon.RefreshRepBarPosition then
                                addon.RefreshRepBarPosition()
                            end
                        end,
                        order = 4
                    },
                    repbar_offset = {
                        type = 'range',
                        name = "Rep Bar Offset",
                        desc = "Y offset when XP bar is not shown",
                        min = 0,
                        max = 50,
                        step = 1,
                        get = function()
                            return addon.db.profile.xprepbar.repbar_offset
                        end,
                        set = function(info, value)
                            addon.db.profile.xprepbar.repbar_offset = value
                            if addon.RefreshRepBarPosition then
                                addon.RefreshRepBarPosition()
                            end
                        end,
                        order = 5
                    },
                    exhaustion_tick = {
                        type = 'toggle',
                        name = "Show Exhaustion Tick",
                        desc = "Show the exhaustion tick indicator on the experience bar (blue marker for rested XP). RetailUI hides this completely.",
                        get = function()
                            return addon.db.profile.style.exhaustion_tick
                        end,
                        set = function(info, val)
                            addon.db.profile.style.exhaustion_tick = val
                            if addon.UpdateExhaustionTick then
                                addon.UpdateExhaustionTick()
                            end
                        end,
                        order = 6
                    },
                    expbar_scale = {
                        type = 'range',
                        name = "Experience Bar Scale",
                        desc = "Scale size of the experience bar",
                        min = 0.5,
                        max = 1.5,
                        step = 0.05,
                        get = function()
                            return addon.db.profile.xprepbar.expbar_scale
                        end,
                        set = function(info, value)
                            addon.db.profile.xprepbar.expbar_scale = value
                            if addon.RefreshXpBarPosition then
                                addon.RefreshXpBarPosition()
                            end
                        end,
                        order = 7
                    },
                    repbar_scale = {
                        type = 'range',
                        name = "Reputation Bar Scale",
                        desc = "Scale size of the reputation bar",
                        min = 0.5,
                        max = 1.5,
                        step = 0.05,
                        get = function()
                            return addon.db.profile.xprepbar.repbar_scale
                        end,
                        set = function(info, value)
                            addon.db.profile.xprepbar.repbar_scale = value
                            if addon.RefreshRepBarPosition then
                                addon.RefreshRepBarPosition()
                            end
                        end,
                        order = 8
                    }
                }
            },

            style = {
                type = 'group',
                name = "Gryphons",
                order = 7,
                args = {
                    gryphons = {
                        type = 'select',
                        name = "Gryphon Style",
                        desc = "Display style for the action bar end-cap gryphons.",
                        values = function()
                            local order = {'old', 'new', 'flying', 'none'}
                            local labels = {
                                old = "Old",
                                new = "New",
                                flying = "Flying",
                                none = "Hide Gryphons"
                            }
                            local t = {}
                            for _, k in ipairs(order) do
                                t[k] = labels[k]
                            end
                            return t
                        end,
                        get = function()
                            return addon.db.profile.style.gryphons
                        end,
                        set = function(info, val)
                            addon.db.profile.style.gryphons = val
                            if addon.RefreshMainbars then
                                addon.RefreshMainbars()
                            end
                        end,
                        order = 1
                    },
                    spacer = {
                        type = 'description',
                        name = " ", -- Espacio visual extra
                        order = 1.5
                    },
                    gryphon_previews = {
                        type = 'description',
                        name = "|cffFFD700Old|r:      |TInterface\\AddOns\\DragonUI\\assets\\uiactionbar2x_:96:96:0:0:512:2048:1:357:209:543|t |TInterface\\AddOns\\DragonUI\\media\\uiactionbar2x_:96:96:0:0:512:2048:1:357:545:879|t\n" ..
                            "|cffFFD700New|r:      |TInterface\\AddOns\\DragonUI\\assets\\uiactionbar2x_new:96:96:0:0:512:2048:1:357:209:543|t |TInterface\\AddOns\\DragonUI\\media\\uiactionbar2x_new:96:96:0:0:512:2048:1:357:545:879|t\n" ..
                            "|cffFFD700Flying|r: |TInterface\\AddOns\\DragonUI\\assets\\uiactionbar2x_flying:105:105:0:0:256:2048:1:158:149:342|t |TInterface\\AddOns\\DragonUI\\media\\uiactionbar2x_flying:105:105:0:0:256:2048:1:157:539:732|t",
                        order = 2
                    }
                }
            },

            additional = {
                type = 'group',
                name = "Additional Bars",
                desc = "Specialized bars that appear when needed (stance/pet/vehicle/totems)",
                order = 8,
                args = {
                    info_header = {
                        type = 'description',
                        name = "|cffFFD700Additional Bars Configuration|r\n" ..
                            "|cff00FF00Auto-show bars:|r Stance (Warriors/Druids/DKs) • Pet (Hunters/Warlocks/DKs) • Vehicle (All classes) • Totem (Shamans)",
                        order = 0
                    },

                    -- COMPACT COMMON SETTINGS
                    common_group = {
                        type = 'group',
                        name = "Common Settings",
                        inline = true,
                        order = 1,
                        args = {
                            size = {
                                type = 'range',
                                name = "Button Size",
                                desc = "Size of buttons for all additional bars",
                                min = 15,
                                max = 50,
                                step = 1,
                                get = function()
                                    return addon.db.profile.additional.size
                                end,
                                set = function(info, value)
                                    addon.db.profile.additional.size = value
                                    if addon.RefreshStance then
                                        addon.RefreshStance()
                                    end
                                    if addon.RefreshPetbar then
                                        addon.RefreshPetbar()
                                    end
                                    if addon.RefreshVehicle then
                                        addon.RefreshVehicle()
                                    end
                                    if addon.RefreshMulticast then
                                        addon.RefreshMulticast()
                                    end
                                end,
                                order = 1,
                                width = "half"
                            },
                            spacing = {
                                type = 'range',
                                name = "Button Spacing",
                                desc = "Space between buttons for all additional bars",
                                min = 0,
                                max = 20,
                                step = 1,
                                get = function()
                                    return addon.db.profile.additional.spacing
                                end,
                                set = function(info, value)
                                    addon.db.profile.additional.spacing = value
                                    if addon.RefreshStance then
                                        addon.RefreshStance()
                                    end
                                    if addon.RefreshPetbar then
                                        addon.RefreshPetbar()
                                    end
                                    if addon.RefreshVehicle then
                                        addon.RefreshVehicle()
                                    end
                                    if addon.RefreshMulticast then
                                        addon.RefreshMulticast()
                                    end
                                end,
                                order = 2,
                                width = "half"
                            }
                        }
                    },

                    -- INDIVIDUAL BARS - ORGANIZED IN 2x2 GRID
                    individual_bars_group = {
                        type = 'group',
                        name = "Individual Bar Positions & Settings",
                        desc = "|cffFFD700Now using Smart Anchoring:|r Bars automatically position relative to each other",
                        inline = true,
                        order = 2,
                        args = {
                            -- TOP ROW: STANCE AND PET
                            stance_group = {
                                type = 'group',
                                name = "Stance Bar",
                                desc = "Warriors, Druids, Death Knights",
                                inline = true,
                                order = 1,
                                args = {
                                    x_position = {
                                        type = 'range',
                                        name = "X Position",
                                        desc = "Horizontal position of stance bar from screen center. Negative values move left, positive values move right.",
                                        min = -1500,
                                        max = 1500,
                                        step = 1,
                                        get = function()
                                            return addon.db.profile.additional.stance.x_position
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.additional.stance.x_position = value
                                            if addon.RefreshStance then
                                                addon.RefreshStance()
                                            end
                                        end,
                                        order = 1,
                                        width = "full"
                                    },
                                    y_offset = {
                                        type = 'range',
                                        name = "Y Offset",
                                        desc = "|cff00FF00Static Positioning:|r The stance bar uses a fixed position from the bottom of the screen (base Y=200).\n" ..
                                            "|cffFFFF00Y Offset:|r Additional vertical adjustment added to the base position.\n" ..
                                            "|cffFFD700Note:|r Positive values move the bar up, negative values move it down.",
                                        min = -1500,
                                        max = 1500,
                                        step = 1,
                                        get = function()
                                            return addon.db.profile.additional.stance.y_offset
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.additional.stance.y_offset = value
                                            if addon.RefreshStance then
                                                addon.RefreshStance()
                                            end
                                        end,
                                        order = 2,
                                        width = "full"
                                    },
                                    button_size = {
                                        type = 'range',
                                        name = "Button Size",
                                        desc = "Size of individual stance buttons in pixels.",
                                        min = 16,
                                        max = 64,
                                        step = 1,
                                        get = function()
                                            return addon.db.profile.additional.stance.button_size
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.additional.stance.button_size = value
                                            if addon.RefreshStance then
                                                addon.RefreshStance()
                                            end
                                        end,
                                        order = 3,
                                        width = "full"
                                    },
                                    button_spacing = {
                                        type = 'range',
                                        name = "Button Spacing",
                                        desc = "Space between stance buttons in pixels.",
                                        min = 0,
                                        max = 20,
                                        step = 1,
                                        get = function()
                                            return addon.db.profile.additional.stance.button_spacing
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.additional.stance.button_spacing = value
                                            if addon.RefreshStance then
                                                addon.RefreshStance()
                                            end
                                        end,
                                        order = 4,
                                        width = "full"
                                    }
                                }
                            },
                            pet_group = {
                                type = 'group',
                                name = "Pet Bar",
                                desc = "Hunters, Warlocks, Death Knights",
                                inline = true,
                                order = 2,
                                args = {
                                    x_position = {
                                        type = 'range',
                                        name = "X Position",
                                        desc = "Horizontal position of pet bar",
                                        min = -500,
                                        max = 500,
                                        step = 1,
                                        get = function()
                                            return addon.db.profile.additional.pet.x_position
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.additional.pet.x_position = value
                                            if addon.RefreshPetbar then
                                                addon.RefreshPetbar()
                                            end
                                        end,
                                        order = 1,
                                        width = "double"
                                    },
                                    y_offset = {
                                        type = 'range',
                                        name = "Y Offset",
                                        desc = "|cffFFD700Smart Anchored Bar:|r This bar automatically positions itself relative to other visible bars.\n\n• This Y offset adds extra spacing above/below the automatic position\n• Positive values = move UP\n• Negative values = move DOWN\n• The bar will still move automatically when you show/hide other action bars",
                                        min = -100,
                                        max = 100,
                                        step = 1,
                                        get = function()
                                            return addon.db.profile.additional.pet.y_offset or 0
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.additional.pet.y_offset = value
                                            if addon.RefreshPetbar then
                                                addon.RefreshPetbar()
                                            end
                                        end,
                                        order = 2,
                                        width = "full"
                                    },
                                    grid = {
                                        type = 'toggle',
                                        name = "Show Empty Slots",
                                        desc = "Display empty action slots on pet bar",
                                        get = function()
                                            return addon.db.profile.additional.pet.grid
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.additional.pet.grid = value
                                            if addon.RefreshPetbar then
                                                addon.RefreshPetbar()
                                            end
                                        end,
                                        order = 3,
                                        width = "full"
                                    }
                                }
                            },

                            -- BOTTOM ROW: VEHICLE AND TOTEM
                            vehicle_group = {
                                type = 'group',
                                name = "Vehicle Bar",
                                desc = "All classes (vehicles/special mounts)",
                                inline = true,
                                order = 3,
                                args = {
                                    x_position = {
                                        type = 'range',
                                        name = "X Position",
                                        desc = "Horizontal position of vehicle bar",
                                        min = -500,
                                        max = 500,
                                        step = 1,
                                        get = function()
                                            return (addon.db.profile.additional.vehicle and
                                                       addon.db.profile.additional.vehicle.x_position) or 0
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.additional.vehicle.x_position = value
                                            if addon.RefreshVehicle then
                                                addon.RefreshVehicle()
                                            end
                                        end,
                                        order = 1,
                                        width = "double"
                                    },
                                    artstyle = {
                                        type = 'toggle',
                                        name = "Blizzard Art Style",
                                        desc = "Use Blizzard original bar arts style",
                                        get = function()
                                            return addon.db.profile.additional.vehicle.artstyle
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.additional.vehicle.artstyle = value
                                            if addon.RefreshVehicle then
                                                addon.RefreshVehicle()
                                            end
                                        end,
                                        order = 2,
                                        width = "full"
                                    }
                                }
                            },
                            totem_group = {
                                type = 'group',
                                name = "Totem Bar",
                                desc = "Shamans only (multicast)",
                                inline = true,
                                order = 4,
                                args = {
                                    x_position = {
                                        type = 'range',
                                        name = "X Position",
                                        desc = "Horizontal offset for totem bar",
                                        min = -500,
                                        max = 500,
                                        step = 1,
                                        order = 1,
                                        get = function()
                                            return (addon.db.profile.additional.totem and
                                                       addon.db.profile.additional.totem.x_position) or 0
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.additional.totem.x_position = value
                                            if addon.RefreshMulticast then
                                                addon.RefreshMulticast()
                                            end
                                        end
                                    },
                                    y_offset = {
                                        type = 'range',
                                        name = "Y Offset",
                                        desc = "Vertical offset for totem bar",
                                        min = -200,
                                        max = 200,
                                        step = 1,
                                        order = 2,
                                        get = function()
                                            return (addon.db.profile.additional.totem and
                                                       addon.db.profile.additional.totem.y_offset) or 0
                                        end,
                                        set = function(info, value)
                                            addon.db.profile.additional.totem.y_offset = value
                                            if addon.RefreshMulticast then
                                                addon.RefreshMulticast()
                                            end
                                        end
                                    }
                                }
                            }
                        }
                    }
                }
            },

            questtracker = {
                name = "Quest Tracker",
                type = "group",
                order = 9,
                args = {
                    description = {
                        type = 'description',
                        name = "Configures the quest objective tracker position and behavior.",
                        order = 1
                    },
                    show_header = {
                        type = 'toggle',
                        name = "Show Header Background",
                        desc = "Show/hide the decorative header background texture",
                        get = function()
                            return addon.db.profile.questtracker.show_header ~= false
                        end,
                        set = function(_, value)
                            addon.db.profile.questtracker.show_header = value
                            if addon.RefreshQuestTracker then
                                addon.RefreshQuestTracker()
                            end
                        end,
                        order = 1.5
                    },
                    x = {
                        type = "range",
                        name = "X Position",
                        desc = "Horizontal position offset",
                        min = -500,
                        max = 500,
                        step = 1,
                        get = function()
                            return addon.db.profile.questtracker.x
                        end,
                        set = function(_, value)
                            addon.db.profile.questtracker.x = value
                            if addon.RefreshQuestTracker then
                                addon.RefreshQuestTracker()
                            end
                        end,
                        order = 2
                    },
                    y = {
                        type = "range",
                        name = "Y Position",
                        desc = "Vertical position offset",
                        min = -500,
                        max = 500,
                        step = 1,
                        get = function()
                            return addon.db.profile.questtracker.y
                        end,
                        set = function(_, value)
                            addon.db.profile.questtracker.y = value
                            if addon.RefreshQuestTracker then
                                addon.RefreshQuestTracker()
                            end
                        end,
                        order = 3
                    },
                    anchor = {
                        type = 'select',
                        name = "Anchor Point",
                        desc = "Screen anchor point for the quest tracker",
                        values = {
                            ["TOPRIGHT"] = "Top Right",
                            ["TOPLEFT"] = "Top Left",
                            ["BOTTOMRIGHT"] = "Bottom Right",
                            ["BOTTOMLEFT"] = "Bottom Left",
                            ["CENTER"] = "Center"
                        },
                        get = function()
                            return addon.db.profile.questtracker.anchor
                        end,
                        set = function(_, value)
                            addon.db.profile.questtracker.anchor = value
                            if addon.RefreshQuestTracker then
                                addon.RefreshQuestTracker()
                            end
                        end,
                        order = 4
                    },
                    reset_position = {
                        type = 'execute',
                        name = "Reset Position",
                        desc = "Reset quest tracker to default position",
                        func = function()
                            addon.db.profile.questtracker.anchor = "TOPRIGHT"
                            addon.db.profile.questtracker.x = -140
                            addon.db.profile.questtracker.y = -255
                            if addon.RefreshQuestTracker then
                                addon.RefreshQuestTracker()
                            end
                        end,
                        order = 5
                    }
                }
            },

            minimap = {
                name = "Minimap",
                type = "group",
                order = 10,
                args = {
                    --  CONFIGURACIONES BÁSICAS DEL MINIMAP
                    scale = {
                        type = "range",
                        name = "Scale",
                        min = 0.5,
                        max = 2,
                        step = 0.1,
                        get = function()
                            return addon.db.profile.minimap.scale
                        end,
                        set = function(_, val)
                            addon.db.profile.minimap.scale = val
                            if addon.MinimapModule then
                                addon.MinimapModule:UpdateSettings()
                            end
                        end,
                        order = 1
                    },
                    border_alpha = {
                        type = 'range',
                        name = "Border Alpha",
                        desc = "Top border alpha (0 to hide)",
                        min = 0,
                        max = 1,
                        step = 0.1,
                        get = function()
                            return addon.db.profile.minimap.border_alpha
                        end,
                        set = function(info, value)
                            addon.db.profile.minimap.border_alpha = value
                            if MinimapBorderTop then
                                MinimapBorderTop:SetAlpha(value)
                            end
                        end,
                        order = 2
                    },
                    

                    addon_button_skin = {
                        type = 'toggle',
                        name = "Addon Button Skin",
                        desc = "Apply DragonUI border styling to addon icons (e.g., bag addons)",
                        get = function()
                            return addon.db.profile.minimap.addon_button_skin
                        end,
                        set = function(info, value)
                            addon.db.profile.minimap.addon_button_skin = value
                            if addon.RefreshMinimap then
                                addon:RefreshMinimap()
                            end
                        end,
                        order = 5.1
                    },

                    addon_button_fade = {
                        type = 'toggle',
                        name = "Addon Button Fade",
                        desc = "Addon icons fade out when not hovered (requires Addon Button Skin)",
                        disabled = function()
                            return not addon.db.profile.minimap.addon_button_skin
                        end,
                        get = function()
                            return addon.db.profile.minimap.addon_button_fade
                        end,
                        set = function(info, value)
                            addon.db.profile.minimap.addon_button_fade = value
                            if addon.RefreshMinimap then
                                addon:RefreshMinimap()
                            end
                        end,
                        order = 5.1
                    },

                    player_arrow_size = {
                        type = 'range',
                        name = "Player Arrow Size",
                        desc = "Size of the player arrow on the minimap",
                        min = 8,
                        max = 50,
                        step = 1,
                        get = function()
                            return addon.db.profile.minimap.player_arrow_size
                        end,
                        set = function(info, value)
                            addon.db.profile.minimap.player_arrow_size = value
                            if addon.MinimapModule then
                                addon.MinimapModule:UpdateSettings()
                            end
                        end,
                        order = 6
                    },

                    --  SECCIÓN TIEMPO Y CALENDARIO INTEGRADA
                    time_header = {
                        type = 'header',
                        name = "Time & Calendar",
                        order = 4.5
                    },
                    clock = {
                        type = 'toggle',
                        name = "Show Clock",
                        desc = "Show/hide the minimap clock",
                        get = function()
                            return addon.db.profile.minimap.clock
                        end,
                        set = function(info, value)
                            addon.db.profile.minimap.clock = value
                            if addon.MinimapModule then
                                addon.MinimapModule:UpdateSettings()
                            end
                        end,
                        order = 4.6
                    },
                    calendar = {
                        type = 'toggle',
                        name = "Show Calendar",
                        desc = "Show/hide the calendar frame",
                        get = function()
                            return addon.db.profile.minimap.calendar
                        end,
                        set = function(info, value)
                            addon.db.profile.minimap.calendar = value
                            if GameTimeFrame then
                                if value then
                                    GameTimeFrame:Show()
                                else
                                    GameTimeFrame:Hide()
                                end
                            end
                        end,
                        order = 4.7
                    },
                    clock_font_size = {
                        type = 'range',
                        name = "Clock Font Size",
                        desc = "Font size for the clock numbers on the minimap",
                        min = 8,
                        max = 20,
                        step = 1,
                        get = function()
                            return addon.db.profile.minimap.clock_font_size
                        end,
                        set = function(info, value)
                            addon.db.profile.minimap.clock_font_size = value
                            if addon.MinimapModule then
                                addon.MinimapModule:UpdateSettings()
                            end
                        end,
                        order = 4.8
                    },

                    --  OTRAS CONFIGURACIONES DEL MINIMAP
                    display_header = {
                        type = 'header',
                        name = "Display Settings",
                        order = 5
                    },
                    tracking_icons = {
                        type = "toggle",
                        name = "Tracking Icons",
                        desc = "Show current tracking icons (old style)",
                        get = function()
                            return addon.db.profile.minimap.tracking_icons
                        end,
                        set = function(_, val)
                            addon.db.profile.minimap.tracking_icons = val
                            if addon.MinimapModule then
                                addon.MinimapModule:UpdateTrackingIcon()
                            end
                        end,
                        order = 5
                    },
                    zoom_buttons = {
                        type = 'toggle',
                        name = "Zoom Buttons",
                        desc = "Show zoom buttons (+/-)",
                        get = function()
                            return addon.db.profile.minimap.zoom_buttons
                        end,
                        set = function(info, value)
                            addon.db.profile.minimap.zoom_buttons = value
                            if MinimapZoomIn and MinimapZoomOut then
                                if value then
                                    MinimapZoomIn:Show()
                                    MinimapZoomOut:Show()
                                else
                                    MinimapZoomIn:Hide()
                                    MinimapZoomOut:Hide()
                                end
                            end
                        end,
                        order = 5
                    },

                    blip_skin = {
                        type = 'toggle',
                        name = "New Blip Style",
                        desc = "Use new DragonUI object icons on the minimap. When disabled, uses classic Blizzard icons.",
                        get = function()
                            return addon.db.profile.minimap.blip_skin
                        end,
                        set = function(info, value)
                            addon.db.profile.minimap.blip_skin = value
                            if addon.MinimapModule then
                                addon.MinimapModule:UpdateSettings()
                            end
                        end,
                        order = 5
                    },
                    zonetext_font_size = {
                        type = 'range',
                        name = "Zone Text Size",
                        desc = "Zone text font size on top border",
                        min = 8,
                        max = 20,
                        step = 1,
                        get = function()
                            return addon.db.profile.minimap.zonetext_font_size
                        end,
                        set = function(info, value)
                            addon.db.profile.minimap.zonetext_font_size = value
                            if MinimapZoneText then
                                local font, _, flags = MinimapZoneText:GetFont()
                                MinimapZoneText:SetFont(font, value, flags)
                            end
                        end,
                        order = 5.1
                    },

                    --  POSICIONAMIENTO
                    position_header = {
                        type = 'header',
                        name = "Position",
                        order = 6
                    },
                    position_reset = {
                        type = 'execute',
                        name = "Reset Position",
                        desc = "Reset minimap to default position (top-right corner)",
                        func = function()
                            --  SOLO RESETEAR SISTEMA WIDGETS
                            if not addon.db.profile.widgets then
                                addon.db.profile.widgets = {}
                            end

                            addon.db.profile.widgets.minimap = {
                                anchor = "TOPRIGHT",
                                posX = 0,
                                posY = 0
                            }

                            if addon.MinimapModule then
                                addon.MinimapModule:UpdateSettings()
                            end

                            print("|cFF00FF00[DragonUI]|r Minimap position reset to default")
                        end,
                        order = 6.2
                    }
                }
            },

            castbars = {
                type = 'group',
                name = "Cast Bars",
                order = 4,
                args = {
                    player_castbar = {
                        type = 'group',
                        name = "Player Castbar",
                        order = 1,
                        args = {
                            sizeX = {
                                type = 'range',
                                name = "Width",
                                desc = "Width of the cast bar",
                                min = 80,
                                max = 512,
                                step = 1,
                                get = function()
                                    return addon.db.profile.castbar.sizeX
                                end,
                                set = function(info, val)
                                    addon.db.profile.castbar.sizeX = val
                                    addon.RefreshCastbar()
                                end,
                                order = 1
                            },
                            sizeY = {
                                type = 'range',
                                name = "Height",
                                desc = "Height of the cast bar",
                                min = 10,
                                max = 64,
                                step = 1,
                                get = function()
                                    return addon.db.profile.castbar.sizeY
                                end,
                                set = function(info, val)
                                    addon.db.profile.castbar.sizeY = val
                                    addon.RefreshCastbar()
                                end,
                                order = 2
                            },
                            scale = {
                                type = 'range',
                                name = "Scale",
                                desc = "Size scale of the cast bar",
                                min = 0.5,
                                max = 2.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.castbar.scale
                                end,
                                set = function(info, val)
                                    addon.db.profile.castbar.scale = val
                                    addon.RefreshCastbar()
                                end,
                                order = 3
                            },
                            showIcon = {
                                type = 'toggle',
                                name = "Show Icon",
                                desc = "Show the spell icon next to the cast bar",
                                get = function()
                                    return addon.db.profile.castbar.showIcon
                                end,
                                set = function(info, val)
                                    addon.db.profile.castbar.showIcon = val
                                    addon.RefreshCastbar()
                                end,
                                order = 4
                            },
                            sizeIcon = {
                                type = 'range',
                                name = "Icon Size",
                                desc = "Size of the spell icon",
                                min = 1,
                                max = 64,
                                step = 1,
                                get = function()
                                    return addon.db.profile.castbar.sizeIcon
                                end,
                                set = function(info, val)
                                    addon.db.profile.castbar.sizeIcon = val
                                    addon.RefreshCastbar()
                                end,
                                order = 5,
                                disabled = function()
                                    return not addon.db.profile.castbar.showIcon
                                end
                            },
                            text_mode = {
                                type = 'select',
                                name = "Text Mode",
                                desc = "Choose how to display spell text: Simple (centered spell name only) or Detailed (spell name + time)",
                                values = {
                                    simple = "Simple (Centered Name Only)",
                                    detailed = "Detailed (Name + Time)"
                                },
                                get = function()
                                    return addon.db.profile.castbar.text_mode or "simple"
                                end,
                                set = function(info, val)
                                    addon.db.profile.castbar.text_mode = val
                                    addon.RefreshCastbar()
                                end,
                                order = 6
                            },
                            precision_time = {
                                type = 'range',
                                name = "Time Precision",
                                desc = "Decimal places for remaining time",
                                min = 0,
                                max = 3,
                                step = 1,
                                get = function()
                                    return addon.db.profile.castbar.precision_time
                                end,
                                set = function(info, val)
                                    addon.db.profile.castbar.precision_time = val
                                end,
                                order = 7,
                                disabled = function()
                                    return addon.db.profile.castbar.text_mode == "simple"
                                end
                            },
                            precision_max = {
                                type = 'range',
                                name = "Max Time Precision",
                                desc = "Decimal places for total time",
                                min = 0,
                                max = 3,
                                step = 1,
                                get = function()
                                    return addon.db.profile.castbar.precision_max
                                end,
                                set = function(info, val)
                                    addon.db.profile.castbar.precision_max = val
                                end,
                                order = 8,
                                disabled = function()
                                    return addon.db.profile.castbar.text_mode == "simple"
                                end
                            },
                            holdTime = {
                                type = 'range',
                                name = "Hold Time (Success)",
                                desc = "How long the bar stays visible after a successful cast.",
                                min = 0,
                                max = 2,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.castbar.holdTime
                                end,
                                set = function(info, val)
                                    addon.db.profile.castbar.holdTime = val
                                    addon.RefreshCastbar()
                                end,
                                order = 9
                            },
                            holdTimeInterrupt = {
                                type = 'range',
                                name = "Hold Time (Interrupt)",
                                desc = "How long the bar stays visible after being interrupted.",
                                min = 0,
                                max = 2,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.castbar.holdTimeInterrupt
                                end,
                                set = function(info, val)
                                    addon.db.profile.castbar.holdTimeInterrupt = val
                                    addon.RefreshCastbar()
                                end,
                                order = 10
                            },
                            reset_position = {
                                type = 'execute',
                                name = "Reset Position",
                                desc = "Resets the X and Y position to default.",
                                func = function()
                                    addon.db.profile.castbar.x_position = addon.defaults.profile.castbar.x_position
                                    addon.db.profile.castbar.y_position = addon.defaults.profile.castbar.y_position
                                    addon.RefreshCastbar()
                                end,
                                order = 11
                            }
                        }
                    },

                    target_castbar = {
                        type = 'group',
                        name = "Target Castbar",
                        order = 2,
                        args = {
                            sizeX = {
                                type = 'range',
                                name = "Width",
                                desc = "Width of the target castbar",
                                min = 50,
                                max = 400,
                                step = 1,
                                get = function()
                                    return addon.db.profile.castbar.target and addon.db.profile.castbar.target.sizeX or
                                               150
                                end,
                                set = function(info, val)
                                    if not addon.db.profile.castbar.target then
                                        addon.db.profile.castbar.target = {}
                                    end
                                    addon.db.profile.castbar.target.sizeX = val
                                    addon.RefreshTargetCastbar()
                                end,
                                order = 1
                            },
                            sizeY = {
                                type = 'range',
                                name = "Height",
                                desc = "Height of the target castbar",
                                min = 5,
                                max = 50,
                                step = 1,
                                get = function()
                                    return addon.db.profile.castbar.target and addon.db.profile.castbar.target.sizeY or
                                               10
                                end,
                                set = function(info, val)
                                    if not addon.db.profile.castbar.target then
                                        addon.db.profile.castbar.target = {}
                                    end
                                    addon.db.profile.castbar.target.sizeY = val
                                    addon.RefreshTargetCastbar()
                                end,
                                order = 2
                            },
                            scale = {
                                type = 'range',
                                name = "Scale",
                                desc = "Scale of the target castbar",
                                min = 0.5,
                                max = 2.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.castbar.target and addon.db.profile.castbar.target.scale or
                                               1
                                end,
                                set = function(info, val)
                                    if not addon.db.profile.castbar.target then
                                        addon.db.profile.castbar.target = {}
                                    end
                                    addon.db.profile.castbar.target.scale = val
                                    addon.RefreshTargetCastbar()
                                end,
                                order = 3
                            },
                            showIcon = {
                                type = 'toggle',
                                name = "Show Spell Icon",
                                desc = "Show the spell icon next to the target castbar",
                                get = function()
                                    if not addon.db.profile.castbar.target then
                                        return true
                                    end
                                    local value = addon.db.profile.castbar.target.showIcon
                                    if value == nil then
                                        return true
                                    end
                                    return value == true
                                end,
                                set = function(info, val)
                                    if not addon.db.profile.castbar.target then
                                        addon.db.profile.castbar.target = {}
                                    end
                                    addon.db.profile.castbar.target.showIcon = val
                                    addon.RefreshTargetCastbar()
                                end,
                                order = 4
                            },
                            sizeIcon = {
                                type = 'range',
                                name = "Icon Size",
                                desc = "Size of the spell icon",
                                min = 10,
                                max = 50,
                                step = 1,
                                get = function()
                                    return
                                        addon.db.profile.castbar.target and addon.db.profile.castbar.target.sizeIcon or
                                            20
                                end,
                                set = function(info, val)
                                    if not addon.db.profile.castbar.target then
                                        addon.db.profile.castbar.target = {}
                                    end
                                    addon.db.profile.castbar.target.sizeIcon = val
                                    addon.RefreshTargetCastbar()
                                end,
                                order = 5,
                                disabled = function()
                                    return not (addon.db.profile.castbar.target and
                                               addon.db.profile.castbar.target.showIcon)
                                end
                            },
                            text_mode = {
                                type = 'select',
                                name = "Text Mode",
                                desc = "Choose how to display spell text: Simple (centered spell name only) or Detailed (spell name + time)",
                                values = {
                                    simple = "Simple (Centered Name Only)",
                                    detailed = "Detailed (Name + Time)"
                                },
                                get = function()
                                    return (addon.db.profile.castbar.target and
                                               addon.db.profile.castbar.target.text_mode) or "simple"
                                end,
                                set = function(info, val)
                                    if not addon.db.profile.castbar.target then
                                        addon.db.profile.castbar.target = {}
                                    end
                                    addon.db.profile.castbar.target.text_mode = val
                                    addon.RefreshTargetCastbar()
                                end,
                                order = 6
                            },
                            precision_time = {
                                type = 'range',
                                name = "Time Precision",
                                desc = "Decimal places for remaining time",
                                min = 0,
                                max = 3,
                                step = 1,
                                get = function()
                                    return (addon.db.profile.castbar.target and
                                               addon.db.profile.castbar.target.precision_time) or 1
                                end,
                                set = function(info, val)
                                    if not addon.db.profile.castbar.target then
                                        addon.db.profile.castbar.target = {}
                                    end
                                    addon.db.profile.castbar.target.precision_time = val
                                end,
                                order = 7,
                                disabled = function()
                                    --  CORRECCIÓN LÓGICA: Deshabilitar si el modo es "simple"
                                    return (addon.db.profile.castbar.target and
                                               addon.db.profile.castbar.target.text_mode) == "simple"
                                end
                            },
                            precision_max = {
                                type = 'range',
                                name = "Max Time Precision",
                                desc = "Decimal places for total time",
                                min = 0,
                                max = 3,
                                step = 1,
                                get = function()
                                    return (addon.db.profile.castbar.target and
                                               addon.db.profile.castbar.target.precision_max) or 1
                                end,
                                set = function(info, val)
                                    if not addon.db.profile.castbar.target then
                                        addon.db.profile.castbar.target = {}
                                    end
                                    addon.db.profile.castbar.target.precision_max = val
                                end,
                                order = 8,
                                disabled = function()
                                    --  CORRECCIÓN LÓGICA: Deshabilitar si el modo es "simple"
                                    return (addon.db.profile.castbar.target and
                                               addon.db.profile.castbar.target.text_mode) == "simple"
                                end
                            },
                            autoAdjust = {
                                type = 'toggle',
                                name = "Auto Adjust for Auras",
                                desc = "Automatically adjust position based on target auras (CRITICAL FEATURE)",
                                get = function()
                                    if not addon.db.profile.castbar.target then
                                        return true
                                    end
                                    local value = addon.db.profile.castbar.target.autoAdjust
                                    if value == nil then
                                        return true
                                    end
                                    return value == true
                                end,
                                set = function(info, val)
                                    if not addon.db.profile.castbar.target then
                                        addon.db.profile.castbar.target = {}
                                    end
                                    addon.db.profile.castbar.target.autoAdjust = val
                                    addon.RefreshTargetCastbar()
                                end,
                                order = 9
                            },
                            holdTime = {
                                type = 'range',
                                name = "Hold Time (Success)",
                                desc = "How long to show the castbar after successful completion",
                                min = 0,
                                max = 3,
                                step = 0.1,
                                get = function()
                                    return
                                        addon.db.profile.castbar.target and addon.db.profile.castbar.target.holdTime or
                                            0.3
                                end,
                                set = function(info, val)
                                    if not addon.db.profile.castbar.target then
                                        addon.db.profile.castbar.target = {}
                                    end
                                    addon.db.profile.castbar.target.holdTime = val
                                    addon.RefreshTargetCastbar()
                                end,
                                order = 10
                            },
                            holdTimeInterrupt = {
                                type = 'range',
                                name = "Hold Time (Interrupt)",
                                desc = "How long to show the castbar after interruption/failure",
                                min = 0,
                                max = 3,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.castbar.target and
                                               addon.db.profile.castbar.target.holdTimeInterrupt or 0.8
                                end,
                                set = function(info, val)
                                    if not addon.db.profile.castbar.target then
                                        addon.db.profile.castbar.target = {}
                                    end
                                    addon.db.profile.castbar.target.holdTimeInterrupt = val
                                    addon.RefreshTargetCastbar()
                                end,
                                order = 11
                            },
                            reset_position = {
                                type = 'execute',
                                name = "Reset Position",
                                desc = "Reset target castbar position to default",
                                func = function()
                                    if not addon.db.profile.castbar.target then
                                        addon.db.profile.castbar.target = {}
                                    end
                                    addon.db.profile.castbar.target.x_position = -20
                                    addon.db.profile.castbar.target.y_position = -20
                                    addon.RefreshTargetCastbar()
                                end,
                                order = 12
                            }
                        }
                    },

                    focus_castbar = {
                        type = 'group',
                        name = "Focus Castbar",
                        order = 3,
                        args = {
                            sizeX = {
                                type = 'range',
                                name = "Width",
                                desc = "Width of the focus castbar",
                                min = 50,
                                max = 400,
                                step = 1,
                                get = function()
                                    return addon.db.profile.castbar.focus.sizeX or 200
                                end,
                                set = function(info, value)
                                    addon.db.profile.castbar.focus.sizeX = value
                                    if addon.RefreshFocusCastbar then
                                        addon.RefreshFocusCastbar()
                                    end
                                end,
                                order = 1
                            },
                            sizeY = {
                                type = 'range',
                                name = "Height",
                                desc = "Height of the focus castbar",
                                min = 5,
                                max = 50,
                                step = 1,
                                get = function()
                                    return addon.db.profile.castbar.focus.sizeY or 16
                                end,
                                set = function(info, value)
                                    addon.db.profile.castbar.focus.sizeY = value
                                    if addon.RefreshFocusCastbar then
                                        addon.RefreshFocusCastbar()
                                    end
                                end,
                                order = 2
                            },
                            scale = {
                                type = 'range',
                                name = "Scale",
                                desc = "Scale of the focus castbar",
                                min = 0.5,
                                max = 2.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.castbar.focus.scale or 1
                                end,
                                set = function(info, value)
                                    addon.db.profile.castbar.focus.scale = value
                                    if addon.RefreshFocusCastbar then
                                        addon.RefreshFocusCastbar()
                                    end
                                end,
                                order = 3
                            },
                            showIcon = {
                                type = 'toggle',
                                name = "Show Icon",
                                desc = "Show the spell icon next to the focus castbar",
                                get = function()
                                    return addon.db.profile.castbar.focus.showIcon
                                end,
                                set = function(info, value)
                                    addon.db.profile.castbar.focus.showIcon = value
                                    if addon.RefreshFocusCastbar then
                                        addon.RefreshFocusCastbar()
                                    end
                                end,
                                order = 4
                            },
                            sizeIcon = {
                                type = 'range',
                                name = "Icon Size",
                                desc = "Size of the spell icon",
                                min = 10,
                                max = 50,
                                step = 1,
                                get = function()
                                    return addon.db.profile.castbar.focus.sizeIcon or 20
                                end,
                                set = function(info, value)
                                    addon.db.profile.castbar.focus.sizeIcon = value
                                    if addon.RefreshFocusCastbar then
                                        addon.RefreshFocusCastbar()
                                    end
                                end,
                                order = 5,
                                disabled = function()
                                    return not addon.db.profile.castbar.focus.showIcon
                                end
                            },
                            text_mode = {
                                type = 'select',
                                name = "Text Mode",
                                desc = "Choose how to display spell text: Simple (centered spell name only) or Detailed (spell name + time)",
                                values = {
                                    simple = "Simple",
                                    detailed = "Detailed"
                                },
                                get = function()
                                    return addon.db.profile.castbar.focus.text_mode or "detailed"
                                end,
                                set = function(info, value)
                                    addon.db.profile.castbar.focus.text_mode = value
                                    if addon.RefreshFocusCastbar then
                                        addon.RefreshFocusCastbar()
                                    end
                                end,
                                order = 6
                            },
                            precision_time = {
                                type = 'range',
                                name = "Time Precision",
                                desc = "Decimal places for remaining time",
                                min = 0,
                                max = 3,
                                step = 1,
                                get = function()
                                    return addon.db.profile.castbar.focus.precision_time or 1
                                end,
                                set = function(info, val)
                                    addon.db.profile.castbar.focus.precision_time = val
                                end,
                                order = 7,
                                disabled = function()
                                    return addon.db.profile.castbar.focus.text_mode == "simple"
                                end
                            },
                            precision_max = {
                                type = 'range',
                                name = "Max Time Precision",
                                desc = "Decimal places for total time",
                                min = 0,
                                max = 3,
                                step = 1,
                                get = function()
                                    return addon.db.profile.castbar.focus.precision_max or 1
                                end,
                                set = function(info, val)
                                    addon.db.profile.castbar.focus.precision_max = val
                                end,
                                order = 8,
                                disabled = function()
                                    return addon.db.profile.castbar.focus.text_mode == "simple"
                                end
                            },
                            autoAdjust = {
                                type = 'toggle',
                                name = "Auto Adjust for Auras",
                                desc = "Automatically adjust position based on focus auras",
                                get = function()
                                    return addon.db.profile.castbar.focus.autoAdjust
                                end,
                                set = function(info, value)
                                    addon.db.profile.castbar.focus.autoAdjust = value
                                    if addon.RefreshFocusCastbar then
                                        addon.RefreshFocusCastbar()
                                    end
                                end,
                                order = 9
                            },
                            holdTime = {
                                type = 'range',
                                name = "Hold Time (Success)",
                                desc = "Time to show the castbar after successful cast completion",
                                min = 0,
                                max = 3.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.castbar.focus.holdTime or 0.3
                                end,
                                set = function(info, value)
                                    addon.db.profile.castbar.focus.holdTime = value
                                    if addon.RefreshFocusCastbar then
                                        addon.RefreshFocusCastbar()
                                    end
                                end,
                                order = 10
                            },
                            holdTimeInterrupt = {
                                type = 'range',
                                name = "Hold Time (Interrupt)",
                                desc = "Time to show the castbar after cast interruption",
                                min = 0,
                                max = 3.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.castbar.focus.holdTimeInterrupt or 0.8
                                end,
                                set = function(info, value)
                                    addon.db.profile.castbar.focus.holdTimeInterrupt = value
                                    if addon.RefreshFocusCastbar then
                                        addon.RefreshFocusCastbar()
                                    end
                                end,
                                order = 11
                            },
                            reset_position = {
                                type = 'execute',
                                name = "Reset Position",
                                desc = "Reset focus castbar position to default",
                                func = function()
                                    local defaults = addon.defaults.profile.castbar.focus
                                    addon.db.profile.castbar.focus.x_position = defaults.x_position
                                    addon.db.profile.castbar.focus.y_position = defaults.y_position
                                    addon.RefreshFocusCastbar()
                                end,
                                order = 12
                            }
                        }
                    }
                }
            },

            unitframe = {
                type = 'group',
                name = "Unit Frames",
                order = 5,
                args = {
                    general = {
                        type = 'group',
                        name = "General",
                        inline = true,
                        order = 1,
                        args = {
                            scale = {
                                type = 'range',
                                name = "Global Scale",
                                desc = "Global scale for all unit frames",
                                min = 0.5,
                                max = 2.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.unitframe.scale
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.scale = value
                                    --  TRIGGER DIRECTO SIN THROTTLING
                                    if addon.RefreshUnitFrames then
                                        addon.RefreshUnitFrames()
                                    end
                                end,
                                order = 1
                            }
                        }
                    },

                    player = {
                        type = 'group',
                        name = "Player Frame",
                        order = 2,
                        args = {
                            scale = {
                                type = 'range',
                                name = "Scale",
                                desc = "Scale of the player frame",
                                min = 0.5,
                                max = 2.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.unitframe.player.scale
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.player.scale = value
                                    --  REFRESH AUTOMÁTICO
                                    if addon.PlayerFrame and addon.PlayerFrame.RefreshPlayerFrame then
                                        addon.PlayerFrame.RefreshPlayerFrame()
                                    end
                                end,
                                order = 1
                            },
                            classcolor = {
                                type = 'toggle',
                                name = "Class Color",
                                desc = "Use class color for health bar",
                                get = function()
                                    return addon.db.profile.unitframe.player.classcolor
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.player.classcolor = value
                                    --  TRIGGER INMEDIATO
                                    if addon.PlayerFrame and addon.PlayerFrame.UpdatePlayerHealthBarColor then
                                        addon.PlayerFrame.UpdatePlayerHealthBarColor()
                                    end
                                end,
                                order = 2
                            },
                            breakUpLargeNumbers = {
                                type = 'toggle',
                                name = "Large Numbers",
                                desc = "Format large numbers (1k, 1m)",
                                get = function()
                                    return addon.db.profile.unitframe.player.breakUpLargeNumbers
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.player.breakUpLargeNumbers = value
                                    --  AUTO-REFRESH
                                    if addon.PlayerFrame and addon.PlayerFrame.RefreshPlayerFrame then
                                        addon.PlayerFrame.RefreshPlayerFrame()
                                    end
                                end,
                                order = 3
                            },
                            textFormat = {
                                type = 'select',
                                name = "Text Format",
                                desc = "How to display health and mana values",
                                values = {
                                    numeric = "Current Value Only",
                                    percentage = "Percentage Only",
                                    both = "Both (Numbers + Percentage)",
                                    formatted = "Current/Max Values"
                                },
                                get = function()
                                    return addon.db.profile.unitframe.player.textFormat
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.player.textFormat = value
                                    --  AUTO-REFRESH
                                    if addon.PlayerFrame and addon.PlayerFrame.RefreshPlayerFrame then
                                        addon.PlayerFrame.RefreshPlayerFrame()
                                    end
                                end,
                                order = 4
                            },
                            showHealthTextAlways = {
                                type = 'toggle',
                                name = "Always Show Health Text",
                                desc = "Show health text always (true) or only on hover (false)",
                                get = function()
                                    return addon.db.profile.unitframe.player.showHealthTextAlways
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.player.showHealthTextAlways = value
                                    --  AUTO-REFRESH
                                    if addon.PlayerFrame and addon.PlayerFrame.RefreshPlayerFrame then
                                        addon.PlayerFrame.RefreshPlayerFrame()
                                    end
                                end,
                                order = 5
                            },
                            showManaTextAlways = {
                                type = 'toggle',
                                name = "Always Show Mana Text",
                                desc = "Show mana/power text always (true) or only on hover (false)",
                                get = function()
                                    return addon.db.profile.unitframe.player.showManaTextAlways
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.player.showManaTextAlways = value
                                    --  AUTO-REFRESH
                                    if addon.PlayerFrame and addon.PlayerFrame.RefreshPlayerFrame then
                                        addon.PlayerFrame.RefreshPlayerFrame()
                                    end
                                end,
                                order = 6
                            },

                            dragon_decoration = {
                                type = 'select',
                                name = "Dragon Decoration",
                                desc = "Add decorative dragon to your player frame for a premium look",
                                values = {
                                    none = "None",
                                    elite = "Elite Dragon (Golden)",
                                    rareelite = "RareElite Dragon (Winged)"
                                },
                                get = function()
                                    return addon.db.profile.unitframe.player.dragon_decoration or "none"
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.player.dragon_decoration = value
                                    --  AUTO-REFRESH
                                    if addon.PlayerFrame and addon.PlayerFrame.RefreshPlayerFrame then
                                        addon.PlayerFrame.RefreshPlayerFrame()
                                    end
                                end,
                                order = 10
                            },
                            alwaysShowAlternateManaText = {
                                type = 'toggle',
                                name = "Always Show Alternate Mana Text",
                                desc = "Show mana text always visible (default: hover only)",
                                get = function()
                                    return addon.db.profile.unitframe.player.alwaysShowAlternateManaText
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.player.alwaysShowAlternateManaText = value
                                    -- Apply immediately if player config exists
                                    if addon.PlayerFrame and addon.PlayerFrame.RefreshPlayerFrame then
                                        addon.PlayerFrame.RefreshPlayerFrame()
                                    end
                                end,
                                order = 11
                            },
                            alternateManaFormat = {
                                type = 'select',
                                name = "Alternate Mana Text Format",
                                desc = "Choose text format for alternate mana display",
                                values = {
                                    numeric = "Current Value Only",
                                    formatted = "Current / Max",
                                    percentage = "Percentage Only",
                                    both = "Percentage + Current/Max"
                                },
                                get = function()
                                    return addon.db.profile.unitframe.player.alternateManaFormat or "both"
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.player.alternateManaFormat = value
                                    -- Apply immediately if player config exists
                                    if addon.PlayerFrame and addon.PlayerFrame.RefreshPlayerFrame then
                                        addon.PlayerFrame.RefreshPlayerFrame()
                                    end
                                end,
                                order = 12
                            }
                        }
                    },

                    target = {
                        type = 'group',
                        name = "Target Frame",
                        order = 3,
                        args = {
                            scale = {
                                type = 'range',
                                name = "Scale",
                                desc = "Scale of the target frame",
                                min = 0.5,
                                max = 2.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.unitframe.target.scale
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.target.scale = value
                                    --  AUTO-REFRESH
                                    if addon.TargetFrame and addon.TargetFrame.RefreshTargetFrame then
                                        addon.TargetFrame.RefreshTargetFrame()
                                    end
                                end,
                                order = 1
                            },
                            classcolor = {
                                type = 'toggle',
                                name = "Class Color",
                                desc = "Use class color for health bar",
                                get = function()
                                    return addon.db.profile.unitframe.target.classcolor
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.target.classcolor = value
                                    --  TRIGGER INMEDIATO
                                    if addon.TargetFrame and addon.TargetFrame.UpdateTargetHealthBarColor then
                                        addon.TargetFrame.UpdateTargetHealthBarColor()
                                    end
                                end,
                                order = 2
                            },
                            breakUpLargeNumbers = {
                                type = 'toggle',
                                name = "Large Numbers",
                                desc = "Format large numbers (1k, 1m)",
                                get = function()
                                    return addon.db.profile.unitframe.target.breakUpLargeNumbers
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.target.breakUpLargeNumbers = value
                                    --  AUTO-REFRESH
                                    if addon.TargetFrame and addon.TargetFrame.RefreshTargetFrame then
                                        addon.TargetFrame.RefreshTargetFrame()
                                    end
                                end,
                                order = 3
                            },
                            textFormat = {
                                type = 'select',
                                name = "Text Format",
                                desc = "How to display health and mana values",
                                values = {
                                    numeric = "Current Value Only",
                                    percentage = "Percentage Only",
                                    both = "Both (Numbers + Percentage)",
                                    formatted = "Current/Max Values"
                                },
                                get = function()
                                    return addon.db.profile.unitframe.target.textFormat
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.target.textFormat = value
                                    --  AUTO-REFRESH
                                    if addon.TargetFrame and addon.TargetFrame.RefreshTargetFrame then
                                        addon.TargetFrame.RefreshTargetFrame()
                                    end
                                end,
                                order = 4
                            },
                            showHealthTextAlways = {
                                type = 'toggle',
                                name = "Always Show Health Text",
                                desc = "Show health text always (true) or only on hover (false)",
                                get = function()
                                    return addon.db.profile.unitframe.target.showHealthTextAlways
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.target.showHealthTextAlways = value
                                    --  AUTO-REFRESH
                                    if addon.TargetFrame and addon.TargetFrame.RefreshTargetFrame then
                                        addon.TargetFrame.RefreshTargetFrame()
                                    end
                                end,
                                order = 5
                            },
                            showManaTextAlways = {
                                type = 'toggle',
                                name = "Always Show Mana Text",
                                desc = "Show mana/power text always (true) or only on hover (false)",
                                get = function()
                                    return addon.db.profile.unitframe.target.showManaTextAlways
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.target.showManaTextAlways = value
                                    --  AUTO-REFRESH
                                    if addon.TargetFrame and addon.TargetFrame.RefreshTargetFrame then
                                        addon.TargetFrame.RefreshTargetFrame()
                                    end
                                end,
                                order = 6
                            },
                            enableThreatGlow = {
                                type = 'toggle',
                                name = "Threat Glow",
                                desc = "Show threat glow effect",
                                get = function()
                                    return addon.db.profile.unitframe.target.enableThreatGlow
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.target.enableThreatGlow = value
                                    --  AUTO-REFRESH
                                    if addon.TargetFrame and addon.TargetFrame.RefreshTargetFrame then
                                        addon.TargetFrame.RefreshTargetFrame()
                                    end
                                end,
                                order = 7
                            }
                        }
                    },

                    tot = {
                        type = 'group',
                        name = "Target of Target",
                        order = 4,
                        args = {
                            scale = {
                                type = 'range',
                                name = "Scale",
                                desc = "Scale of the target of target frame",
                                min = 0.5,
                                max = 2.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.unitframe.tot.scale
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.tot.scale = value
                                    if addon.TargetOfTarget and addon.TargetOfTarget.RefreshToTFrame then
                                        addon.TargetOfTarget.RefreshToTFrame()
                                    end
                                end,
                                order = 1
                            },
                            classcolor = {
                                type = 'toggle',
                                name = "Class Color",
                                desc = "Use class color for health bar",
                                get = function()
                                    return addon.db.profile.unitframe.tot.classcolor
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.tot.classcolor = value
                                    if addon.TargetOfTarget and addon.TargetOfTarget.RefreshToTFrame then
                                        addon.TargetOfTarget.RefreshToTFrame()
                                    end
                                end,
                                order = 2
                            },
                            x = {
                                type = 'range',
                                name = "X Position",
                                desc = "Horizontal position offset",
                                min = -200,
                                max = 200,
                                step = 1,
                                get = function()
                                    return addon.db.profile.unitframe.tot.x
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.tot.x = value
                                    if addon.TargetOfTarget and addon.TargetOfTarget.RefreshToTFrame then
                                        addon.TargetOfTarget.RefreshToTFrame()
                                    end
                                end,
                                order = 3
                            },
                            y = {
                                type = 'range',
                                name = "Y Position",
                                desc = "Vertical position offset",
                                min = -200,
                                max = 200,
                                step = 1,
                                get = function()
                                    return addon.db.profile.unitframe.tot.y
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.tot.y = value
                                    if addon.TargetOfTarget and addon.TargetOfTarget.RefreshToTFrame then
                                        addon.TargetOfTarget.RefreshToTFrame()
                                    end
                                end,
                                order = 4
                            }
                        }
                    },

                    fot = {
                        type = 'group',
                        name = "Target of Focus",
                        order = 4.5,
                        args = {
                            scale = {
                                type = 'range',
                                name = "Scale",
                                desc = "Scale of the focus of target frame",
                                min = 0.5,
                                max = 2.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.unitframe.fot.scale
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.fot.scale = value
                                    if addon.TargetOfFocus and addon.TargetOfFocus.RefreshToFFrame then
                                        addon.TargetOfFocus.RefreshToFFrame()
                                    end
                                end,
                                order = 1
                            },
                            classcolor = {
                                type = 'toggle',
                                name = "Class Color",
                                desc = "Use class color for health bar",
                                get = function()
                                    return addon.db.profile.unitframe.fot.classcolor
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.fot.classcolor = value
                                    if addon.TargetOfFocus and addon.TargetOfFocus.RefreshToFFrame then
                                        addon.TargetOfFocus.RefreshToFFrame()
                                    end
                                end,
                                order = 2
                            },
                            x = {
                                type = 'range',
                                name = "X Position",
                                desc = "Horizontal position offset",
                                min = -200,
                                max = 200,
                                step = 1,
                                get = function()
                                    return addon.db.profile.unitframe.fot.x
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.fot.x = value
                                    if addon.TargetOfFocus and addon.TargetOfFocus.RefreshToFFrame then
                                        addon.TargetOfFocus.RefreshToFFrame()
                                    end
                                end,
                                order = 3
                            },
                            y = {
                                type = 'range',
                                name = "Y Position",
                                desc = "Vertical position offset",
                                min = -200,
                                max = 200,
                                step = 1,
                                get = function()
                                    return addon.db.profile.unitframe.fot.y
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.fot.y = value
                                    if addon.TargetOfFocus and addon.TargetOfFocus.RefreshToFFrame then
                                        addon.TargetOfFocus.RefreshToFFrame()
                                    end
                                end,
                                order = 4
                            }
                        }
                    },

                    focus = {
                        type = 'group',
                        name = "Focus Frame",
                        order = 5,
                        args = {
                            scale = {
                                type = 'range',
                                name = "Scale",
                                desc = "Scale of the focus frame",
                                min = 0.5,
                                max = 2.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.unitframe.focus.scale
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.focus.scale = value
                                    if addon.RefreshFocusFrame then
                                        addon.RefreshFocusFrame()
                                    end
                                end,
                                order = 1
                            },
                            classcolor = {
                                type = 'toggle',
                                name = "Class Color",
                                desc = "Use class color for health bar",
                                get = function()
                                    return addon.db.profile.unitframe.focus.classcolor
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.focus.classcolor = value
                                    if addon.RefreshFocusFrame then
                                        addon.RefreshFocusFrame()
                                    end
                                end,
                                order = 2
                            },
                            breakUpLargeNumbers = {
                                type = 'toggle',
                                name = "Large Numbers",
                                desc = "Format large numbers (1k, 1m)",
                                get = function()
                                    return addon.db.profile.unitframe.focus.breakUpLargeNumbers
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.focus.breakUpLargeNumbers = value
                                    if addon.RefreshFocusFrame then
                                        addon.RefreshFocusFrame()
                                    end
                                end,
                                order = 3
                            },
                            textFormat = {
                                type = 'select',
                                name = "Text Format",
                                desc = "How to display health and mana values",
                                values = {
                                    numeric = "Current Value Only",
                                    percentage = "Percentage Only",
                                    both = "Both (Numbers + Percentage)",
                                    formatted = "Current/Max Values"
                                },
                                get = function()
                                    return addon.db.profile.unitframe.focus.textFormat
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.focus.textFormat = value
                                    if addon.RefreshFocusFrame then
                                        addon.RefreshFocusFrame()
                                    end
                                end,
                                order = 4
                            },
                            showHealthTextAlways = {
                                type = 'toggle',
                                name = "Always Show Health Text",
                                desc = "Show health text always (true) or only on hover (false)",
                                get = function()
                                    return addon.db.profile.unitframe.focus.showHealthTextAlways
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.focus.showHealthTextAlways = value
                                    if addon.RefreshFocusFrame then
                                        addon.RefreshFocusFrame()
                                    end
                                end,
                                order = 5
                            },
                            showManaTextAlways = {
                                type = 'toggle',
                                name = "Always Show Mana Text",
                                desc = "Show mana/power text always (true) or only on hover (false)",
                                get = function()
                                    return addon.db.profile.unitframe.focus.showManaTextAlways
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.focus.showManaTextAlways = value
                                    if addon.RefreshFocusFrame then
                                        addon.RefreshFocusFrame()
                                    end
                                end,
                                order = 6
                            },
                            override = {
                                type = 'toggle',
                                name = "Override Position",
                                desc = "Override default positioning",
                                get = function()
                                    return addon.db.profile.unitframe.focus.override
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.focus.override = value
                                    if addon.RefreshFocusFrame then
                                        addon.RefreshFocusFrame()
                                    end
                                end,
                                order = 6
                            }
                            -- X/Y Position options removed - now using centralized widget system
                        }
                    },

                    pet = {
                        type = 'group',
                        name = "Pet Frame",
                        order = 6,
                        args = {
                            scale = {
                                type = 'range',
                                name = "Scale",
                                desc = "Scale of the pet frame",
                                min = 0.5,
                                max = 2.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.unitframe.pet.scale
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.pet.scale = value
                                    if addon.RefreshPetFrame then
                                        addon.RefreshPetFrame()
                                    end
                                end,
                                order = 1
                            },
                            textFormat = {
                                type = 'select',
                                name = "Text Format",
                                desc = "How to display health and mana values",
                                values = {
                                    numeric = "Current Value Only",
                                    percentage = "Percentage Only",
                                    both = "Both (Numbers + Percentage)",
                                    formatted = "Current/Max Values"
                                },
                                get = function()
                                    return addon.db.profile.unitframe.pet.textFormat
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.pet.textFormat = value
                                    if addon.RefreshPetFrame then
                                        addon.RefreshPetFrame()
                                    end
                                end,
                                order = 2
                            },
                            breakUpLargeNumbers = {
                                type = 'toggle',
                                name = "Large Numbers",
                                desc = "Format large numbers (1k, 1m)",
                                get = function()
                                    return addon.db.profile.unitframe.pet.breakUpLargeNumbers
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.pet.breakUpLargeNumbers = value
                                    if addon.RefreshPetFrame then
                                        addon.RefreshPetFrame()
                                    end
                                end,
                                order = 3
                            },
                            showHealthTextAlways = {
                                type = 'toggle',
                                name = "Always Show Health Text",
                                desc = "Always display health text (otherwise only on mouseover)",
                                get = function()
                                    return addon.db.profile.unitframe.pet.showHealthTextAlways
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.pet.showHealthTextAlways = value
                                    if addon.RefreshPetFrame then
                                        addon.RefreshPetFrame()
                                    end
                                end,
                                order = 4
                            },
                            showManaTextAlways = {
                                type = 'toggle',
                                name = "Always Show Mana Text",
                                desc = "Always display mana/energy/rage text (otherwise only on mouseover)",
                                get = function()
                                    return addon.db.profile.unitframe.pet.showManaTextAlways
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.pet.showManaTextAlways = value
                                    if addon.RefreshPetFrame then
                                        addon.RefreshPetFrame()
                                    end
                                end,
                                order = 5
                            },
                            enableThreatGlow = {
                                type = 'toggle',
                                name = "Threat Glow",
                                desc = "Show threat glow effect",
                                get = function()
                                    return addon.db.profile.unitframe.pet.enableThreatGlow
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.pet.enableThreatGlow = value
                                    if addon.RefreshPetFrame then
                                        addon.RefreshPetFrame()
                                    end
                                end,
                                order = 6
                            },
                            override = {
                                type = 'toggle',
                                name = "Override Position",
                                desc = "Allows the pet frame to be moved freely. When unchecked, it will be positioned relative to the player frame.",
                                get = function()
                                    return addon.db.profile.unitframe.pet.override
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.pet.override = value
                                    if addon.RefreshPetFrame then
                                        addon.RefreshPetFrame()
                                    end
                                end,
                                order = 7
                            },
                            -- REMOVED: Anchor options are not needed for a simple movable frame.
                            -- The X and Y coordinates will be relative to the center of the screen when override is active.
                            x = {
                                type = 'range',
                                name = "X Position",
                                desc = "Horizontal position (only active if Override is checked)",
                                min = -2500,
                                max = 2500,
                                step = 1,
                                get = function()
                                    return addon.db.profile.unitframe.pet.x
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.pet.x = value
                                    if addon.RefreshPetFrame then
                                        addon.RefreshPetFrame()
                                    end
                                end,
                                order = 10,
                                disabled = function()
                                    return not addon.db.profile.unitframe.pet.override
                                end
                            },
                            y = {
                                type = 'range',
                                name = "Y Position",
                                desc = "Vertical position (only active if Override is checked)",
                                min = -2500,
                                max = 2500,
                                step = 1,
                                get = function()
                                    return addon.db.profile.unitframe.pet.y
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.pet.y = value
                                    if addon.RefreshPetFrame then
                                        addon.RefreshPetFrame()
                                    end
                                end,
                                order = 11,
                                disabled = function()
                                    return not addon.db.profile.unitframe.pet.override
                                end
                            }
                        }
                    },

                    party = {
                        type = 'group',
                        name = "Party Frames",
                        order = 6,
                        args = {
                            info_text = {
                                type = 'description',
                                name = "|cffFFD700Party Frames Configuration|r\n\nCustom styling for party member frames with automatic health/mana text display and class colors.",
                                order = 0
                            },
                            scale = {
                                type = 'range',
                                name = "Scale",
                                desc = "Scale of party frames",
                                min = 0.5,
                                max = 2.0,
                                step = 0.1,
                                get = function()
                                    return addon.db.profile.unitframe.party.scale
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.party.scale = value
                                    --  AUTO-REFRESH
                                    if addon.RefreshPartyFrames then
                                        addon.RefreshPartyFrames()
                                    end
                                end,
                                order = 1
                            },
                            classcolor = {
                                type = 'toggle',
                                name = "Class Color",
                                desc = "Use class color for health bars in party frames",
                                get = function()
                                    return addon.db.profile.unitframe.party.classcolor
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.party.classcolor = value
                                    --  AUTO-REFRESH
                                    if addon.RefreshPartyFrames then
                                        addon.RefreshPartyFrames()
                                    end
                                end,
                                order = 2
                            },
                            breakUpLargeNumbers = {
                                type = 'toggle',
                                name = "Large Numbers",
                                desc = "Format large numbers (1k, 1m)",
                                get = function()
                                    return addon.db.profile.unitframe.party.breakUpLargeNumbers
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.party.breakUpLargeNumbers = value
                                    --  AUTO-REFRESH
                                    if addon.RefreshPartyFrames then
                                        addon.RefreshPartyFrames()
                                    end
                                end,
                                order = 3
                            },
                            showHealthTextAlways = {
                                type = 'toggle',
                                name = "Always Show Health Text",
                                desc = "Always show health text on party frames (instead of only on hover)",
                                get = function()
                                    return addon.db.profile.unitframe.party.showHealthTextAlways
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.party.showHealthTextAlways = value
                                    if addon.RefreshPartyFrames then
                                        addon.RefreshPartyFrames()
                                    end
                                end,
                                order = 3.1
                            },
                            showManaTextAlways = {
                                type = 'toggle',
                                name = "Always Show Mana Text",
                                desc = "Always show mana text on party frames (instead of only on hover)",
                                get = function()
                                    return addon.db.profile.unitframe.party.showManaTextAlways
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.party.showManaTextAlways = value
                                    if addon.RefreshPartyFrames then
                                        addon.RefreshPartyFrames()
                                    end
                                end,
                                order = 3.2
                            },
                            textFormat = {
                                type = 'select',
                                name = "Text Format",
                                desc = "Choose how to display health and mana text",
                                values = {
                                    ['numeric'] = 'Current Value Only (2345)',
                                    ['formatted'] = 'Formatted Current (2.3k)', 
                                    ['percentage'] = 'Percentage Only (75%)',
                                    ['both'] = 'Percentage + Current (75% | 2.3k)'
                                },
                                get = function()
                                    return addon.db.profile.unitframe.party.textFormat or 'both'
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.party.textFormat = value
                                    if addon.RefreshPartyFrames then
                                        addon.RefreshPartyFrames()
                                    end
                                end,
                                order = 3.3
                            },
                            orientation = {
                                type = 'select',
                                name = "Orientation",
                                desc = "Party frame orientation",
                                values = {
                                    ['vertical'] = 'Vertical',
                                    ['horizontal'] = 'Horizontal'
                                },
                                get = function()
                                    return addon.db.profile.unitframe.party.orientation
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.party.orientation = value
                                    --  AUTO-REFRESH
                                    if addon.RefreshPartyFrames then
                                        addon.RefreshPartyFrames()
                                    end
                                end,
                                order = 4
                            },
                            padding = {
                                type = 'range',
                                name = "Padding",
                                desc = "Space between party frames",
                                min = 0,
                                max = 50,
                                step = 1,
                                get = function()
                                    return addon.db.profile.unitframe.party.padding
                                end,
                                set = function(info, value)
                                    addon.db.profile.unitframe.party.padding = value
                                    --  AUTO-REFRESH
                                    if addon.RefreshPartyFrames then
                                        addon.RefreshPartyFrames()
                                    end
                                end,
                                order = 5
                            },
                           
                        }
                    }
                }
            },

            profiles = (function()
                -- Obtenemos la tabla de opciones de perfiles estándar
                local profileOptions = LibStub("AceDBOptions-3.0"):GetOptionsTable(addon.db)

                -- Modificamos los textos para que sean más concisos
                profileOptions.name = "Profiles"
                profileOptions.desc = "Manage UI settings profiles."
                profileOptions.order = 99

                --  COMPROBAMOS QUE LA TABLA DE PERFIL EXISTE ANTES DE MODIFICARLA
                if profileOptions.args and profileOptions.args.profile then
                    profileOptions.args.profile.name = "Active Profile"
                    profileOptions.args.profile.desc = "Choose the profile to use for your settings."
                end

                -- AÑADIMOS LA DESCRIPCIÓN Y EL BOTÓN DE RECARGA
                profileOptions.args.reload_warning = {
                    type = 'description',
                    name = "\n|cffFFD700It's recommended to reload the UI after switching profiles.|r",
                    order = 15 -- Justo después del selector de perfiles
                }

                profileOptions.args.reload_execute = {
                    type = 'execute',
                    name = "Reload UI",
                    func = function()
                        ReloadUI()
                    end,
                    order = 16 -- Justo después del texto de advertencia
                }

                return profileOptions
            end)()
        }
    }
end
