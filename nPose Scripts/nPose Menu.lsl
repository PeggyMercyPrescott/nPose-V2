/*
The nPose scripts are licensed under the GPLv2 (http://www.gnu.org/licenses/gpl-2.0.txt), with the following addendum:

The nPose scripts are free to be copied, modified, and redistributed, subject to the following conditions:
    - If you distribute the nPose scripts, you must leave them full perms.
    - If you modify the nPose scripts and distribute the modifications, you must also make your modifications full perms.

"Full perms" means having the modify, copy, and transfer permissions enabled in Second Life and/or other virtual world platforms derived from Second Life (such as OpenSim).  If the platform should allow more fine-grained permissions, then "full perms" will mean the most permissive possible set of permissions allowed by the platform.
*/

//default options settings.  Change these to suit personal preferences
string Permissions = "PUBLIC"; //default permit option Pubic, Locked, Group
string curmenuonsit = "off"; //default menuonsit option
string cur2default = "off";  //default action to revert back to default pose when last sitter has stood
string Facials = "on";
string menuReqSit = "off";  //required to be seated to get a menu
string RLVenabled = "on";   //default RLV enabled state  on or no

integer OptionUseDisplayNames;
//

list victims;
//Leona:
//renamed the global var "path" to "GlobalPath" to avoid confusion
//TODO:
//storing the path in global scope could lead to multiuser menu issues, because the path isn't global, but a per user var
//this can't be fixed without changing the syntax of EXTERNAL_UTIL_REQUEST which have to contain the current path
//using the path in global scope will work in most cases, but it isn't nice. I would say: Even if it works, it is wrong.
string GlobalPath;
list slots; //this slots list is not complete. it only contains seated AV key and seat numbers
string defaultPoseNcName; //holds the name of the default notecard.
string menuNC = ".Change Menu Order"; //holds the name of the menu order notecard to read.
//key toucherid;
list menus;
list menuPermPath;
list menuPermPerms;
float currentOffsetDelta = 0.2;
float menuDistance = 30.0;

key scriptID;

#define SET_PREFIX "SET"
#define BTN_PREFIX "BTN"
#define DEFAULT_PREFIX "DEFAULT"
#define CARD_PREFIXES [SET_PREFIX, DEFAULT_PREFIX, BTN_PREFIX]

#define DIALOG -900
#define DIALOG_RESPONSE -901
#define DIALOG_TIMEOUT -902
#define DOPOSE 200
#define ADJUST 201
#define SWAP 202
#define DUMP 204
#define STOPADJUST 205
#define SYNC 206
#define DOBUTTON 207
#define ADJUSTOFFSET 208
#define SETOFFSET 209
#define SWAPTO 210
#define DOREMENU 220
#define NC_READER_REQUEST 224
#define NC_READER_RESPONSE 225
#define UNSIT -222
#define DOMENU -800
#define DOMENU_ACCESSCTRL -801
#define DOMENU_CORE -803
#define PREPARE_REMENU -804
#define USER_PERMISSION_UPDATE -806
#define PLUGIN_MENU_REGISTER -810
#define PLUGIN_MENU_RESPONSE -811
#define PLUGIN_MENU_SHOW -812
#define PLUGIN_MENU_CHANGE_PATH -813
#define MENU_SHOW -815
#define EXTERNAL_UTIL_REQUEST -888
#define MEMORY_USAGE 34334
#define SEAT_UPDATE 35353
#define VICTIMS_LIST -238
#define OPTIONS_NUM -240
#define FACIALS_FLAG -241

//dialog buttons
#define BACKBTN "^"
#define ROOTMENU "Main"

//TODO: option related
#define MENUONSIT "Menuonsit"
#define TODEFUALT "ToDefault"
#define PERMITBTN "Permit"


// userDefinedPermissions
#define PERMISSION_GROUP "group"
#define PERMISSION_OWNER "owner"
#define PERMISSION_SEATED "seated"
#define PERMISSION_OCCUPIED "occupied"
#define PERMISSION_OWNSEAT "ownseat"
#define USER_PERMISSION_TYPE_LIST "list"
#define USER_PERMISSION_TYPE_BOOL "bool"
#define USER_PERMISSION_TYPE_MACRO "macro"
list pluginPermissionList;

//NC Reader
#define NC_READER_CONTENT_SEPARATOR "%&§"

//own plugins related
#define MY_PLUGIN_MENU "npose_menu"
#define MY_PLUGIN_MENU_UNSIT "npose_unsit"
#define MY_PLUGIN_MENU_CHANGE_SEAT "npose_changeseat"
#define MY_PLUGIN_MENU_OFFSET "npose_offset"

#define BUTTON_OFFSET_FWD "forward"
#define BUTTON_OFFSET_BKW "backward"
#define BUTTON_OFFSET_LEFT "left"
#define BUTTON_OFFSET_RIGHT "right"
#define BUTTON_OFFSET_UP "up"
#define BUTTON_OFFSET_DOWN "down"
#define BUTTON_OFFSET_ZERO "reset"
list OFFSET_BUTTONS = [
    BUTTON_OFFSET_FWD, BUTTON_OFFSET_LEFT, BUTTON_OFFSET_UP,
    BUTTON_OFFSET_BKW, BUTTON_OFFSET_RIGHT, BUTTON_OFFSET_DOWN,
    "0.2", "0.1", "0.05",
    "0.01", BUTTON_OFFSET_ZERO
];

//store plugins base paths, register myself as plugin for the rootmenu
list PluginBasePathList=[ROOTMENU];
list PluginNamesList=[MY_PLUGIN_MENU];
list PluginParamsList=[""];

//TODO
#define BUTTON_NAME_SLOT "ChangeSeat"
#define BUTTON_NAME_OFFSET "offset"
#define BUTTON_NAME_UNSIT "Unsit"


debug(list message){
    llOwnerSay((((llGetScriptName() + "\n##########\n#>") + llDumpList2String(message,"\n#>")) + "\n##########"));
}

DoMenu(key rcpt, string path, integer page, string prompt, list additionalButtons) {
    list choices;
    integer index = llListFindList(menus, [path]);
    if(~index) {
        choices=llParseStringKeepNulls(llList2String(menus, index+1), ["|"], []);
    }
    choices+=additionalButtons;
    
    //check menu permissions
    if(
        //the whole if statement only exists for backward compability, because all this (and more) could be done via button permissions on root level
        (rcpt == llGetOwner() || Permissions == "GROUP" && llSameGroup(rcpt) || Permissions == "PUBLIC") &&
        (rcpt == llGetOwner() || menuReqSit == "off" || ~llListFindList(slots, [rcpt])) &&
        // old RLV plugin, (Lenoa: This behaves like gecko release)
        (rcpt == llGetOwner() || !~llListFindList(victims, [(string)rcpt]))
    ) {
        list thisMenuPath=llDeleteSubList(llParseStringKeepNulls(path , [":"], []), 0, 0);
        //check button permission for this path up to the root
        //this also means that button permissions are inheritable
        list tempPath=thisMenuPath;
        integer rcptSlotNumber=llListFindList(slots, [rcpt]);
        if(~rcptSlotNumber) {
            rcptSlotNumber=rcptSlotNumber/2;
        }
        do {
            integer indexc=llListFindList(menuPermPath, [llDumpList2String(tempPath, ":")]);
            if(~indexc) {
                if(!isAllowed(0, rcpt, rcptSlotNumber, llList2String(menuPermPerms, indexc))) {
                    return;
                }
            }
        } while (llGetListLength(tempPath=llDeleteSubList(tempPath, -1, -1)));
        //check button permission for each button
        integer stopc = llGetListLength(choices);
        integer nc;
        for(; nc < stopc; ++nc) {
            integer indexc = llListFindList(menuPermPath, [llDumpList2String(thisMenuPath + llList2String(choices, nc), ":")]);
            if(indexc != -1) {
                if(!isAllowed(0, rcpt, rcptSlotNumber, llList2String(menuPermPerms, indexc))) {
                    choices = llDeleteSubList(choices, nc, nc);
                    --nc;
                    --stopc;
                }
            }
        }
        //generate utility buttons
        //TODO Leona: maybe this could also be done in the dialog script? If yes: double check the RLV+ plugin
        list utilitybuttons;
        if(path != ROOTMENU) {
            utilitybuttons += [BACKBTN];
        }
        //call the dialog
        llMessageLinked(LINK_SET, DIALOG, llDumpList2String([
            (string)rcpt,
            prompt + "\n"+path+"\n",
            (string)page,
            llDumpList2String(choices, "`"),
            llDumpList2String(utilitybuttons, "`"),
            path
        ], "|"), scriptID);
    }
}

integer isAllowed(integer mode, key avatarKey, integer slotNumber, string permissions) {
    // avatarKey: the key of the avatar using the menu

    // mode 0: (menu button check) 
    //    slotNumber: the slot number of the menu user (if the menu user is not in the slot list, provide a -1)

    // mode 1 (slot button check)
    //    slotNumber: the slotnumber for which the button should be created
    
    
    // Syntax of the permission string:
    // The permission string is the last part of the notecard name surrounded by {}
    // it can also be used in the change seat or unsit command
    // It contains KEYWORDS and OPERATORS.

    // OPERATORS (listed in order of their precedence)
    // ! means a logical NOT
    // & means a logical AND
    // ~ means a logical OR
    // Operators may be surrounded by spaces

    // KEYWORDS (case insensitive)
    // owner:
    //        mode 0: returns TRUE if the menu user is the object owner
    //        mode 1: returns TRUE if the object owner is sitting on the specified seat
    // group:
    //        mode 0: returns TRUE if the active group of the menu user is equal to the group of the object
    //        mode 1: returns TRUE if the active group of the user sitting on the specified seat is equal to the group of the object
    // seated:
    //        mode 0: returns TRUE if the menu user is seated
    //        mode 1: no usefull meaning
    // occupied:
    //        mode 0: no usefull meaning
    //        mode 1: returns TRUE if the given slot is in use
    // ownseat:
    //        mode 0: no usefull meaning
    //        mode 1: returns TRUE if the menu user sits in the specified slot
    // any integer counts as a seatNumber:
    //        mode 0: returns TRUE if menu user sits on the seat with the number seatNumber
    //        mode 1: returns TRUE if the specified slotNumber represents the seat with the number seatNumber
    // any other string counts as a UserDefinedPermission

    // Examples:
    // mode 0:
    // 1~3 : is TRUE if the menu user is seated on seat number 1 or 3
    // owner~2 : is TRUE if the menu user is the object owner or if the menu user is sitting on seat number 2
    // owner&!victim : is TRUE if the menu user is the object owner, but only if he/she isn't a victim (victim is a UserDefinedPermission used by the RLV+ plugin)
    // 1~3&group: is TRUE for the user on seat 1 and also for the user on seat 3 if he/she has the same active group as the Object
    permissions=llStringTrim(permissions, STRING_TRIM);
    if(permissions=="") {
        return TRUE;
    }
    else {
        key avatarInSlot;
        if(~slotNumber) {
            avatarInSlot=llList2Key(slots, slotNumber*2);
        }
        list permItemsOr=llParseString2List(llToLower(permissions), ["~"], []);
        integer indexOr=~llGetListLength(permItemsOr);
        integer result;
        while(++indexOr && !result) {
            list permItemsAnd=llParseString2List(llList2String(permItemsOr, indexOr), ["&"], []);
            integer indexAnd=~llGetListLength(permItemsAnd);
            result=TRUE;
            while(++indexAnd && result) {
                integer invert;
                string item=llStringTrim(llList2String(permItemsAnd, indexAnd), STRING_TRIM);
                if(llGetSubString(item, 0, 0)=="!") {
                    invert=TRUE;
                    item=llStringTrim(llDeleteSubString(item, 0, 0), STRING_TRIM);
                }
                if(item==PERMISSION_GROUP) {
                    if(!mode) {
                        result=logicalXor(invert, llSameGroup(avatarKey));
                    }
                    else {
                        result=logicalXor(invert, llSameGroup(avatarInSlot));
                    }
                }
                else if(item==PERMISSION_OWNER) {
                    if(!mode) {
                        result=logicalXor(invert, llGetOwner()==avatarKey);
                    }
                    else {
                        result=logicalXor(invert, llGetOwner()==avatarInSlot);
                    }
                }
                else if(item==PERMISSION_SEATED) {
                    result=logicalXor(invert, slotNumber>=0);
                }
                else if(item==PERMISSION_OCCUPIED) {
                    result=logicalXor(invert, llList2String(slots, slotNumber*2)!="" && llList2String(slots, slotNumber*2)!=NULL_KEY);
                }
                else if(item==PERMISSION_OWNSEAT) {
                    result=logicalXor(invert, avatarKey==avatarInSlot);
                }
                else if((string)((integer)item)==item){
                    result=logicalXor(invert, slotNumber+1==(integer)item);
                }

                else {
                    //maybe a user defined permission
                    integer pluginPermissionIndex=llListFindList(pluginPermissionList, [item]);
                    if(~pluginPermissionIndex) {
                        //plugin permission
                        string pluginPermissionType=llList2String(pluginPermissionList, pluginPermissionIndex+1);
                        if(pluginPermissionType==USER_PERMISSION_TYPE_LIST) {
                            result=logicalXor(invert, ~llSubStringIndex(llList2String(pluginPermissionList, pluginPermissionIndex+2), (string)avatarKey));
                        }
                        else if(pluginPermissionType==USER_PERMISSION_TYPE_BOOL) {
                            result=logicalXor(invert, (integer)llList2String(pluginPermissionList, pluginPermissionIndex+2));
                        }
                        else if(pluginPermissionType==USER_PERMISSION_TYPE_MACRO) {
                            result=logicalXor(invert, isAllowed(mode, avatarKey, slotNumber, llList2String(pluginPermissionList, pluginPermissionIndex+2)));
                        }
                        else {
                            //error unknown plugin permission type
                            //maybe a message to the owner?
                            result=invert;
                        }
                    }
                    else {
                        //maybe the plugin has not registered itself right now. So assume a blank list or a 0 as value
                        result=invert;
                    }
                }
            }
        }
        return result;
    }
}

integer logicalXor(integer conditionA, integer conditionB) {
    //lsl do only know a bitwise XOR :(
    return(conditionA && !conditionB) || (!conditionA && conditionB);
}

BuildMenus(list cardNames) {//builds the user defined menu buttons
    menus = [];
    menuPermPath = [];
    menuPermPerms = [];
    integer stop = llGetListLength(cardNames);
    integer fromContents;
    if(!stop) {
        fromContents = TRUE;
        stop = llGetInventoryNumber(INVENTORY_NOTECARD);
    }
    integer defaultSet;// = FALSE; // false by default
    integer n;
    for(; n<stop; ++n) {//step through the notecards backwards so that default notecard is first in the contents
        string name = llList2String(cardNames, n);
        if(fromContents) {
            name = llGetInventoryName(INVENTORY_NOTECARD, n);
        }
        integer permsIndex1 = llSubStringIndex(name,"{");
        integer permsIndex2 = llSubStringIndex(name,"}");
        string menuPerms;
        if(~permsIndex1) { // found
            menuPerms = llGetSubString(name, permsIndex1+1, permsIndex2+-1);
            name = llDeleteSubString(name, permsIndex1, permsIndex2);
        }
        list pathParts = llParseStringKeepNulls(name, [":"], []);
        string prefix = llList2String(pathParts, 0);
        if((!defaultSet && prefix == SET_PREFIX) | (prefix == DEFAULT_PREFIX)) {
            if(!fromContents) {
                defaultPoseNcName = llList2String(cardNames, n);
            }
            else {
                defaultPoseNcName = llGetInventoryName(INVENTORY_NOTECARD, n);
            }
            defaultSet = TRUE;
        }
        pathParts = llListReplaceList(pathParts, [ROOTMENU], 0, 0);
        if(menuPerms) {
            menuPermPath += llDumpList2String(llDeleteSubList(pathParts, 0, 0), ":");
            menuPermPerms += menuPerms;
        }
        if(~llListFindList(CARD_PREFIXES, [prefix])) { // found
            pathParts = llDeleteSubList(pathParts, 0, 0);            
            while(llGetListLength(pathParts)) {
                string last = llList2String(pathParts, -1);
                string parentpath = llDumpList2String([ROOTMENU] + llDeleteSubList(pathParts, -1, -1), ":");
                integer index = llListFindList(menus, [parentpath]);
                if(~index && !(index & 1)) {
                    list children = llParseStringKeepNulls(llList2String(menus, index + 1), ["|"], []);
                    if(!~llListFindList(children, [last])) {
                        children += [last];
                        if(llGetInventoryType(menuNC) != INVENTORY_NOTECARD) {
                            children = llListSort(children, 1, 1);
                        }
                        menus = llListReplaceList(menus, [llDumpList2String(children, "|")], index + 1, index + 1);
                    }
                }
                else {
                    menus += [parentpath, last];
                }
                pathParts = llDeleteSubList(pathParts, -1, -1);
            }
        }
    }
}

integer getSlotNumber(string menuResponse) {
    //the menuResponse can be:
    //1) seatX: where X is a number
    //2) " " + a seat name
    //3) "∙" + an avatar name + "∙"
    //1 and 2 can be found in our slots list
    //returns the slotNumber
    string prefix=llGetSubString(menuResponse, 0, 0);
    if (prefix=="s") {
        //a seat number
        return (integer)llGetSubString(menuResponse, 4, -1)-1;
    }
    integer length=llGetListLength(slots);
    integer index;
    for(; index<length; index+=2) {
        if(prefix==" ") {
            if(!llSubStringIndex(" " + llList2String(slots, index+1), menuResponse+"§")) {
                return (index)/2;
            }
        }
        else if(prefix=="∙") {
            string nameInSlotList;
            if(OptionUseDisplayNames) {
                nameInSlotList=llGetDisplayName(llList2Key(slots, index));
            }
            else {
                nameInSlotList=llKey2Name(llList2Key(slots, index));
            }
            if(!llSubStringIndex("∙"+nameInSlotList+"∙", menuResponse)) {
                return index/2;
            }
        }
    }
    return -1;
}

string getNcName(string path) {
    path = llDumpList2String(llDeleteSubList(llParseStringKeepNulls(path, [":"], []), 0, 0), ":");
    integer permissionIndex = llListFindList(menuPermPath, [path]);
    if(~permissionIndex) {
        string thisPerm = llList2String(menuPermPerms, permissionIndex);
        if(thisPerm != "") {
            path+="{"+thisPerm+"}";
        }
    }
    if(path!="") {
        path=":"+path;
    }

    string ncName;
    if(llGetInventoryType(ncName=DEFAULT_PREFIX + path) == INVENTORY_NOTECARD) {
        return ncName;
    }
    if(llGetInventoryType(ncName=SET_PREFIX + path) == INVENTORY_NOTECARD) {
        return ncName;
    }
    if(llGetInventoryType(ncName=BTN_PREFIX + path) == INVENTORY_NOTECARD) {
        return ncName;
    }
    return "";
}

string deleteNode(string path, integer start, integer end) {
    return llDumpList2String(llDeleteSubList(llParseStringKeepNulls(path, [":"], []), start, end), ":");
}
string buildParamSet1(string path, integer page, string prompt, list additionalButtons, string pluginName, string pluginLocalPath, string pluginStaticParams) {
    //We can't use colons in the promt, because they are used as a seperator in other messages
    //replace them with a UTF Symbol
    prompt=llDumpList2String(llParseStringKeepNulls(prompt, [","], []), "‚"); // CAUTION: the 2nd "‚" is a UTF sign!
    string buttons=llDumpList2String(additionalButtons, ",");
    return llDumpList2String([path, page, prompt, buttons, pluginName, pluginLocalPath, pluginStaticParams], "|");
}

default{
    state_entry() {
        scriptID=llGetInventoryKey(llGetScriptName());
        if(llGetInventoryType(menuNC) != INVENTORY_NOTECARD) {
            BuildMenus([]);
        }
        else {
            llSleep(1.0); //be sure that the NC reader script finished resetting
            llMessageLinked(LINK_SET, NC_READER_REQUEST, menuNC, scriptID);
        }
    }
    
    touch_start(integer total_number) {
        key toucherKey = llDetectedKey(0);
        vector vDelta = llDetectedPos(0) - llGetPos();
        if(toucherKey == llGetOwner() || llVecMag(vDelta) < menuDistance) {
            //fake a DIALOG_RESPONSE to get the initial Menu, TODO: Leona: perhaps we should do this in the Dialog script?
            llMessageLinked(LINK_SET, DIALOG_RESPONSE, llDumpList2String(["0", "", toucherKey, ROOTMENU], "|"), scriptID);
            //DoMenu(toucherKey, ROOTMENU, 0, "", []);
        }
    }
    
    link_message(integer sender, integer num, string str, key id) {
        integer index;
        integer n;
        integer stop;
        if(str == "menuUP") {
            //TODO: deprecated
            llMessageLinked(LINK_SET, -802, "PATH=" + GlobalPath, id);
        }
        if((num == DIALOG_RESPONSE && id == scriptID )|| num==DOMENU) {
            //the following block is to sort the paramters from the different message (to be backward compatible)
            integer page;
            string selection;
            key toucherid;
            string path;
            string prompt;
            if(num==DOMENU) {
                list params = llParseStringKeepNulls(str, [","], []);  //parse the message
                //str: path[, page[, prompt]]
                path=llList2String(params, 0);
                //next line to be backward compatible
                if(!llSubStringIndex(path, "PATH=")) {
                     path = llGetSubString(path, 5, -1);
                }
                page=(integer)llList2String(params, 1);
                prompt=llList2String(params, 2);
            }
            else {
                list params = llParseStringKeepNulls(str, ["|"], []);  //parse the message
                page = (integer)llList2String(params, 0);  //get the page number
                selection = llList2String(params, 1);  //get the button that was pressed from str
                toucherid = llList2Key(params, 2);
                path = llList2String(params, 3); //get the path from params list
            }
            
            if(path!="" && selection!="") {
                path+=":";
            }
            path+=selection;
            //block end
            
            string paramSet1=buildParamSet1(path, page, prompt, [], "", "", "");
            string ncName=getNcName(path);
            if(ncName) {
                //there is a NC that should be executed
                integer newNum=DOBUTTON;
                if(!llSubStringIndex(ncName, DEFAULT_PREFIX) || !llSubStringIndex(ncName, SET_PREFIX)) {
                    newNum=DOPOSE;
                }
                llMessageLinked(LINK_SET, newNum, ncName + NC_READER_CONTENT_SEPARATOR + paramSet1, toucherid);
            }
            else {
                //no NC to be executed, initiate the remenu process without piping the messages trough the core
                llMessageLinked(LINK_SET, PREPARE_REMENU, paramSet1, toucherid);
            }
        }
        else if(num==PREPARE_REMENU) {
            list params=llParseStringKeepNulls(str, ["|"], []);  //parse the message
            string path=llList2String(params, 0);
            string selection=deleteNode(path, 0, -2);
            integer page=(integer)llList2String(params, 1);  //get the page number
            string prompt=llList2String(params, 2);
            string additionalButtons=llList2String(params, 3);

            //BackButton
            if(selection==BACKBTN) {
                path=deleteNode(path, -2, -1);
                page=0;
            }

            //plugin detection
            string pluginName;
            string pluginLocalPath;
            string pluginStaticParams;
            string pluginBasePath=path;
            while(pluginBasePath!="" && pluginName=="") {
                integer index=llListFindList(PluginBasePathList, [pluginBasePath]);
                if(~index) {
                    pluginName=llList2String(PluginNamesList, index);
                    pluginStaticParams=llList2String(PluginParamsList, index);
                    pluginLocalPath=llDeleteSubString(path, 0, llStringLength(pluginBasePath));
                }
                else {
                    pluginBasePath=deleteNode(pluginBasePath, -1, -1);
                }
            }

            if(pluginName==MY_PLUGIN_MENU) {
            //inside my own plugin
                if(~llListFindList(menus, [path])) {
                    //this is a node
                    page=0;
                    string paramSet1=buildParamSet1(path, page, prompt, [additionalButtons], "", "", "");
                    llMessageLinked(LINK_SET, DOREMENU, getNcName(path) + NC_READER_CONTENT_SEPARATOR + paramSet1, id);
                }
                else if(~llListFindList(menus, [deleteNode(path, -1, -1)])) {
                    //this is a leaf
                    path=deleteNode(path, -1, -1);
                    string paramSet1=buildParamSet1(path, page, prompt, [additionalButtons], "", "", "");
                    llMessageLinked(LINK_SET, PREPARE_REMENU, paramSet1, id);
                }
                else {
                    //TODO: what is it?
                }
            }
            else {
                //inside a foreign plugin
                string paramSet1=buildParamSet1(path, page, prompt, [additionalButtons], pluginName, pluginLocalPath, pluginStaticParams);
                llMessageLinked(LINK_SET, PLUGIN_MENU_RESPONSE, paramSet1, id);
            }
        }
        else if(num==PLUGIN_MENU_SHOW) {
            string path=llList2String(llParseStringKeepNulls(str, ["|"], []), 0);
            llMessageLinked(LINK_SET, DOREMENU, getNcName(path) + NC_READER_CONTENT_SEPARATOR + str, id);
        }
        else if(num==PLUGIN_MENU_REGISTER) {
            list params=llParseStringKeepNulls(str, ["|"], []);
            string basePath=llList2String(params, 0);
            string pluginName=llToLower(llList2String(params, 1));
            string pluginStaticParams=llList2String(params, 2);
            integer index=llListFindList(PluginBasePathList, [basePath]);
            if(~index) {
                PluginNamesList=llListReplaceList(PluginNamesList, [pluginName], index, index);
                PluginParamsList=llListReplaceList(PluginParamsList, [pluginStaticParams], index, index);
            }
            else {
                PluginBasePathList+=basePath;
                PluginNamesList+=pluginName;
                PluginParamsList+=pluginStaticParams;
            }
        }
        else if(num==PLUGIN_MENU_RESPONSE) {
            //the menu script itself contains a few menu plugins.
            //the former admin menu is not part of it. We could simply use NCs for it.
            list params=llParseStringKeepNulls(str, ["|"], []);
            string pluginName=llList2String(params, 4);
            if(pluginName==MY_PLUGIN_MENU_OFFSET) {
                //this is the offset menu. It can be move to any other script easily.
                string path=llList2String(params, 0);
                string pluginLocalPath=llList2String(params, 5);

                if(pluginLocalPath!="") {
                    vector direction;
                    if(pluginLocalPath == BUTTON_OFFSET_FWD) {direction=<1, 0, 0>;}
                    else if(pluginLocalPath == BUTTON_OFFSET_BKW) {direction=<-1, 0, 0>;}
                    else if(pluginLocalPath == BUTTON_OFFSET_LEFT) {direction=<0, 1, 0>;}
                    else if(pluginLocalPath == BUTTON_OFFSET_RIGHT) {direction=<0, -1, 0>;}
                    else if(pluginLocalPath == BUTTON_OFFSET_UP) {direction=<0, 0, 1>;}
                    else if(pluginLocalPath == BUTTON_OFFSET_DOWN) {direction=<0, 0, -1>;}
                    else if(pluginLocalPath == BUTTON_OFFSET_ZERO) {llMessageLinked(LINK_SET, SETOFFSET, (string)ZERO_VECTOR, id);}
                    else {currentOffsetDelta = (float)pluginLocalPath;}
                    if(direction) {
                        llMessageLinked(LINK_SET, ADJUSTOFFSET, (string)(direction * currentOffsetDelta), id);
                    }
                    //one level back
                    path=deleteNode(path, -1, -1);
                }
                string prompt="Adjust by " + (string)currentOffsetDelta+ "m, or choose another distance.";
                llMessageLinked(LINK_SET, PLUGIN_MENU_SHOW, buildParamSet1(path, 0, prompt, OFFSET_BUTTONS, "", "", ""), id);
            }
            else if(pluginName==MY_PLUGIN_MENU_CHANGE_SEAT || pluginName==MY_PLUGIN_MENU_UNSIT) {
                //TODO: Leona: check if nested plugins could be a good
                //idea, because both functions are something like a "pick Seat" function
                //and maybe a "pick Seat" dialog may also be useful in other plugins
                //
                //this is the change seat menu. It should stay inside this script, because it uses the isAllowed function and the slots list. 
                string path=llList2String(params, 0);
                integer page=(integer)llList2String(params, 1);
                string prompt;
                string pluginLocalPath=llList2String(params, 5);
                string pluginStaticParams=llList2String(params, 6);
                
                if(pluginName==MY_PLUGIN_MENU_CHANGE_SEAT) {
                    prompt="Where will you sit?";
                }
                else {
                    prompt="Pick an avatar to unsit.";
                }
                
                if(pluginLocalPath!="") {
                    //a new seat is selected
                    integer remenu=TRUE;
                    integer slotNumber=getSlotNumber(pluginLocalPath);
                    if(~slotNumber) {
                        if(pluginName==MY_PLUGIN_MENU_CHANGE_SEAT) {
                            llMessageLinked(LINK_SET, SWAPTO, (string)(slotNumber+1), id);
                        }
                        else {
                            key avatarToUnsit=llList2Key(slots, n*2);
                            llMessageLinked(LINK_SET, UNSIT, avatarToUnsit, id);
                            if(avatarToUnsit==id) {
                                //don't remenu if someone unsits oneself
                                remenu=FALSE;
                            }
                        }
                    }
                    if(remenu) {
                        path=deleteNode(path, -1, -1);
                        llMessageLinked(LINK_SET, PLUGIN_MENU_CHANGE_PATH, buildParamSet1(path, 0, "", [], "", "", ""), id);
                    }
                    
                }
                if(pluginLocalPath=="") {
                    //build and show the menu
                    //generate the buttons
                    //A button will be
                    //1) if an avatar sits on the seat: "∙" + an avatar name + "∙"
                    //2) if the seat name is provided: " " + a seat name
                    //3) else: seatX: where X is a number
                    integer length=llGetListLength(slots);
                    list buttons;
                    for(index=0; index<length; index+=2) {
                        if(isAllowed(1, id, index/2, pluginStaticParams)) {
                            key avatar=llList2Key(slots, index);
                            list temp=llParseStringKeepNulls(llList2String(slots, index+1), ["§"], []);
                            string seatName=llList2String(temp, 0);
                            string seatNumber=llList2String(temp, 1);
                            if(avatar) {
                                if(OptionUseDisplayNames) {
                                    buttons+="∙"+llGetDisplayName(avatar)+"∙";
                                }
                                else {
                                    buttons+="∙"+llKey2Name(avatar)+"∙";
                                }
                            }
                            else if(seatName) {
                                buttons+=" "+seatName;
                            }
                            else {
                                buttons+=seatNumber;
                            }
                        }
                    }
                    if(pluginLocalPath=="") {
                        page=0;
                    }
                    llMessageLinked(LINK_SET, PLUGIN_MENU_SHOW, buildParamSet1(path, page, prompt, buttons, "", "", ""), id);
                }
            }
        }
        else if(num == DIALOG_TIMEOUT) {//menu not clicked and dialog timed out
            if((cur2default == "on") && (llGetObjectPrimCount(llGetKey()) == llGetNumberOfPrims()) && (defaultPoseNcName != "")) {
                llMessageLinked(LINK_SET, DOPOSE, defaultPoseNcName, NULL_KEY);
            }
//begin handle link message inputs
        }
        else if(num==OPTIONS_NUM) {
            //save new option(s) from LINKMSG
            list optionsToSet = llParseStringKeepNulls(str, ["~"], []);
            stop = llGetListLength(optionsToSet);
            for(; n<stop; ++n) {
                list optionsItems = llParseString2List(llList2String(optionsToSet, n), ["="], []);
                string optionItem = llToLower(llStringTrim(llList2String(optionsItems, 0), STRING_TRIM));
                string optionSetting = llToLower(llStringTrim(llList2String(optionsItems, 1), STRING_TRIM));
                integer optionSettingFlag = optionSetting=="on" || (integer)optionSetting;
                if(optionItem == "menuonsit") {curmenuonsit = optionSetting;}
                else if(optionItem == "permit") {Permissions = llToUpper(optionSetting);}
                else if(optionItem == "2default") {cur2default = optionSetting;}
                else if(optionItem == "sit2getmenu") {menuReqSit = optionSetting;}
                else if(optionItem == "menudist") {menuDistance = (float)optionSetting;}
                else if(optionItem == "facialexp") {
                    Facials = optionSetting;
                    llMessageLinked(LINK_SET, FACIALS_FLAG, Facials, NULL_KEY);
                }
                else if(optionItem == "rlvbaser") {
                    RLVenabled = optionSetting;
                    llMessageLinked(LINK_SET, -1812221819, "RLV=" + RLVenabled, NULL_KEY);
                }
                else if(optionItem == "usedisplaynames") {
                    OptionUseDisplayNames = optionSettingFlag;
                }
            }
        }
        else if(num == MENU_SHOW) {
            list parts=llParseStringKeepNulls(str, ["|"], []);
            DoMenu(id, llList2String(parts, 0), (integer)llList2String(parts, 1), llList2String(parts, 2), llParseString2List(llList2String(parts, 3), [","], []));
        }
        else if(num == DOMENU_ACCESSCTRL) {//external call to check permissions
            //TODO: Deprecated?
            DoMenu(id, ROOTMENU, 0, "", []);
        }
        else if(num == VICTIMS_LIST) {
            //TODO: Deprecated!
            victims = llCSV2List(str);
        }
        else if(num == NC_READER_RESPONSE) {
            if(id==scriptID) {
                BuildMenus(llList2List(llParseStringKeepNulls(str, [NC_READER_CONTENT_SEPARATOR], []), 3, -1));
                str = "";
            }
        }
        else if(num == USER_PERMISSION_UPDATE) {
            // @param str string CSV: permissionName, permissionType, permissionValue[, permissionName, permissionType, permissionValue[, ...]]
            // permissionName: a unique name for a permission. A permission name of the type macro should begin with a @
            // permissionType: bool|list|macro
            // permissionValue:
            //   bool: 0|1
            //   list: a list with Avatar UUIDs (must not contain a ",")
            //   macro: a permission string

            list newPermission=llCSV2List(str);
            integer n;
            integer length=llGetListLength(newPermission);
            for(; n<length; n+=3) {
                string permissionName=llToLower(llList2String(newPermission, n));
                index=llListFindList(pluginPermissionList, [permissionName]);
                if(~index) {
                    pluginPermissionList=llDeleteSubList(pluginPermissionList, index, index+2);
                }
                pluginPermissionList+=[permissionName] + llList2List(newPermission, n+1, n+2);
            }
        }
        else if(num==SEAT_UPDATE) {
            list slotsList = llParseStringKeepNulls(str, ["^"], []);
            slots = [];
            for(n=0; n<(llGetListLength(slotsList)/8); ++n) {
                slots += [(key)llList2String(slotsList, n*8+4), llList2String(slotsList, n*8+7)];
            }
        }
        else if(num == MEMORY_USAGE) {//dump memory stats to local
            llSay(0,"Memory Used by " + llGetScriptName() + ": " + (string)llGetUsedMemory() + " of " + (string)llGetMemoryLimit()
                 + ",Leaving " + (string)llGetFreeMemory() + " memory free.");
        }
//end handle link message inputs
    }

    changed(integer change) {
        if(change & CHANGED_INVENTORY) {
            scriptID=llGetInventoryKey(llGetScriptName());
            if(llGetInventoryType(menuNC) != INVENTORY_NOTECARD) {
                BuildMenus([]);
            }
            else {
                llSleep(1.0); //be sure that the NC reader script finished resetting
                llMessageLinked(LINK_SET, NC_READER_REQUEST, menuNC, scriptID);
            }
        }
        if(change & CHANGED_OWNER) {
            llResetScript();
        }
        if((change & CHANGED_LINK) && (cur2default == "on")
         && (llGetObjectPrimCount(llGetKey()) == llGetNumberOfPrims())
         && (defaultPoseNcName != "")) {
            llMessageLinked(LINK_SET, DOPOSE, defaultPoseNcName, NULL_KEY);
        }
    }

    on_rez(integer params) {
        llResetScript();
    }
}
