-- Do not load at all when player have less than two roles
local tank, healer, damager = UnitGetAvailableRoles("player")
if (tank and 1 or 0) + (healer and 1 or 0) + (damager and 1 or 0) < 2 then return end

local SetSpecialization = C_SpecializationInfo.SetSpecialization or SetSpecialization -- not exact match, but in this addon I don't use second "pet" parameter

local num_specs

local BUTTON     = 1
local WIDTH      = 2
local TEXT_WIDTH = 3
local TEXT       = 4
local HIDDEN     = 5
local DISABLED   = 6
local SPEC       = 7

local token = {}

local max_spec_buttons = 2
local em_button_idx = max_spec_buttons + 1

local function SpecButtonOnClick(self)
   SetSpecialization(self[token][SPEC])
end

local state = {}
local function CreateButtons()
   local prev
   for idx = 1, max_spec_buttons do
      local button = CreateFrame("Button", nil, LFGDungeonReadyDialog, "UIPanelButtonTemplate")
      state[idx] = { [BUTTON] = button, [WIDTH] = 0 }
      button[token] = state[idx]
      button:SetText(TALENT_SPEC_ACTIVATE)
      button:SetWidth(115)
      button:SetHeight(25)
      if prev then
         button:SetPoint("TOP", prev, "BOTTOM", 0, 0)
      else
         -- -42, below BigWigs dungeon timer, 3 - below standard buttons, 45 - above standard buttons, 120 - above spec image, check if it collides with number of killed bosses
         button:SetPoint("BOTTOM", LFGDungeonReadyDialog, "BOTTOM", 0, -46)
      end
      button:SetScript("OnClick", SpecButtonOnClick)
      prev = button
   end

   local em_button = CreateFrame("Button", nil, state[max_spec_buttons][BUTTON], "UIPanelButtonTemplate")
   em_button:SetText(EQUIPMENT_MANAGER)
   em_button:SetHeight(25)
   em_button:SetPoint("TOP", prev, "BOTTOM", 0, 0)
   em_button:SetScript("OnClick", function()
      ToggleCharacter("PaperDollFrame", true)
      PaperDollFrame_SetSidebar(PaperDollFrame, 3)
   end)
   state[em_button_idx] = { [BUTTON] = em_button, [WIDTH] = 0, [TEXT_WIDTH] = em_button:GetTextWidth() }

   -- Looks more aesthetically pleasing to me. Should work with up to 3 buttons.
   state[1], state[max_spec_buttons] = state[max_spec_buttons], state[1]
end
CreateButtons()

local role_icon = {
   TANK    = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:20:20:0:0:64:64:0:19:21:40|t",
   HEALER  = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:20:20:0:0:64:64:20:39:0:19|t",
   DAMAGER = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:20:20:0:0:64:64:20:39:21:40|t",
   NONE    = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:20:20:0:0:64:64:20:39:21:40|t"
}

local function UpdateButton()
   local proposalExists, id, typeID, subtypeID, name, texture, role, hasResponded, totalEncounters, completedEncounters, numMembers, isLeader = GetLFGProposal()
   if not proposalExists then return end

   if not num_specs or num_specs == 0 then
      num_specs = GetNumSpecializations()
   end

   local current_spec = GetSpecialization()
   -- print("need role", role, "num_specs", num_specs)
   local spec_role
   if current_spec then
      spec_role = GetSpecializationRole(current_spec)
   end

   if role == spec_role then
      for idx = 1, max_spec_buttons do
         local button_state = state[idx]
         if not button_state[HIDDEN] then
            button_state[BUTTON]:Hide()
            button_state[HIDDEN] = true
         end
      end
      return
   end

   -- Find suitable specs and write their text/data to buttons
   local need_recalculate_width
   local button_idx = 0
   for spec_idx = num_specs, 1, -1 do
      if spec_idx ~= current_spec then
         local id, name, description, icon, other_spec_role = GetSpecializationInfo(spec_idx)
         -- print("other_spec", spec_idx, "role", other_spec_role)
         if other_spec_role == role then
            -- Found other spec suitable for incoming LFG proposal
            button_idx = button_idx + 1
            local button_state = state[button_idx]
            local text = role_icon[other_spec_role] .. "|T" .. icon .. ":0|t" .. name -- .. " - " .. TALENT_SPEC_ACTIVATE
            if button_state[TEXT] ~= text then
               button_state[BUTTON]:SetText(text)
               button_state[TEXT_WIDTH] = nil
               need_recalculate_width = true
            end
            button_state[SPEC] = spec_idx
         end
      end
      if button_idx == max_spec_buttons then break end
   end

   local max_text_width = state[em_button_idx][TEXT_WIDTH]
   -- Hide inactive / find max text width
   for idx = max_spec_buttons, 1, -1 do
      local button_state = state[idx]
      if idx > button_idx then
         -- Inactive button, hide it
         if not button_state[HIDDEN] then
            button_state[BUTTON]:Hide()
            button_state[HIDDEN] = true
         end
      else
         local text_width = button_state[TEXT_WIDTH]
         if not text_width then
            text_width = button_state[BUTTON]:GetTextWidth()
            button_state[TEXT_WIDTH] = text_width
         end
         if max_text_width < text_width then max_text_width = text_width end
      end
   end
   max_text_width = max_text_width + 30

   -- Set button width
   -- Enable/disable
   -- Show buttons
   local combat_lockdown = InCombatLockdown()
   for idx = 1, em_button_idx do
      local button_state = state[idx]
      local button = button_state[BUTTON]
      if idx <= button_idx or idx == em_button_idx then
         if button[WIDTH] ~= max_text_width then
            button:SetWidth(max_text_width)
            button[WIDTH] = max_text_width
         end
         if idx ~= em_button_idx then
            if combat_lockdown then
               if not button_state[DISABLED] then
                  button:Disable()
                  button_state[DISABLED] = true
               end
            else
               if button_state[DISABLED] then
                  button:Enable()
                  button_state[DISABLED] = nil
               end
            end
         end
         if button_state[HIDDEN] then
            button_state[BUTTON]:Show()
            button_state[HIDDEN] = nil
         end
      end
   end
end

local event_watcher = CreateFrame("Frame", nil, LFGDungeonReadyDialog)
local event_watcher_working = false

local function LFGDungeonReadyPopup_Update_More()
   -- This gets automatically called on ACTIVE_TALENT_GROUP_CHANGED too,
   -- but we will watch event just in case this changes in future.

   local parent_is_shown = LFGDungeonReadyDialog:IsShown()
   if parent_is_shown then
      if not event_watcher_working then
         event_watcher:SetScript("OnEvent", UpdateButton) -- function() print("CAUGHT EVENT") UpdateButton() end
         event_watcher_working = true
      end
      UpdateButton()
   else
      if event_watcher_working then
         event_watcher:SetScript("OnEvent", nil)
         event_watcher_working = false
      end
   end
end
hooksecurefunc("LFGDungeonReadyPopup_Update", LFGDungeonReadyPopup_Update_More)

event_watcher:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
event_watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
event_watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
