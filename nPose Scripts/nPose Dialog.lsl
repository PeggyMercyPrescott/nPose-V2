/*
The nPose scripts are licensed under the GPLv2 (http://www.gnu.org/licenses/gpl-2.0.txt), with the following addendum:

The nPose scripts are free to be copied, modified, and redistributed, subject to the following conditions:
    - If you distribute the nPose scripts, you must leave them full perms.
    - If you modify the nPose scripts and distribute the modifications, you must also make your modifications full perms.

"Full perms" means having the modify, copy, and transfer permissions enabled in Second Life and/or other virtual world platforms derived from Second Life (such as OpenSim).  If the platform should allow more fine-grained permissions, then "full perms" will mean the most permissive possible set of permissions allowed by the platform.
*/
//an adaptation of Schmobag Hogfather's SchmoDialog script

integer DIALOG = -900;
integer DIALOG_RESPONSE = -901;
integer DIALOG_TIMEOUT = -902;

integer PAGE_SIZE = 12;
integer MEMORY_USAGE = 34334;
string MORE = "More";
//string BACKBTN = "^";
//string SWAPBTN = "swap";
//string SYNCBTN = "sync";
string BLANK = " ";
integer TIMEOUT = 60;
integer REPEAT = 5;//how often the timer will go off, in seconds
integer Channel;
integer Listener = -1;

list Menus;//8-strided list in form [recipient, dialogid, starttime, prompt, list buttons, page buttons, currentpage, path]
//where "list buttons" means the big list of choices presented to the user
//and "page buttons" means utility buttons that will appear on every page, such as one saying "go up one level"
//and "currentpage" is an integer meaning which page of the menu the user is currently viewing

integer STRIDE_LENGTH = 8;

list Avs;//fill this on start and update on changed_link.  leave dialogs open until avs stand

string Utf8Trim(string s, integer iLen) {
    // This trims a string to iLen bytes interpreted as utf8 (not utf16).
    // The string returned will be utf16, but when interpreted as utf8,
    // it will be iLen bytes (not characters) or shorter.  Also, because
    // of the use of base64, it's best if iLen is a multiple of 3.  If
    // it's not, it will be rounded down to a multiple of 3 if trimming
    // is needed.  If trimming isn't needed, it will be unchanged regardless
    // of original length.
    string s2 = llStringToBase64(s);
    iLen = (iLen / 3) * 4; // This winds up being a multiple of 4, rounded down.
    if (llStringLength(s2) > iLen) {
        return llBase64ToString(llGetSubString(s2, 0, --iLen));
    }
    return s;
}

list SeatedAvs() {
    //like AvCount() but returns a list of seated avs, starting with lowest link number and moving up from there
    list avs;
    integer linkcount = llGetNumberOfPrims();
    integer n;
    for (n = linkcount; n >= 0; n--) {
        key id = llGetLinkKey(n);
        if (llGetAgentSize(id) != ZERO_VECTOR) {
            //it's a real av. add to list
            avs = [id] + avs;//adding it this way prevents having to reverse the av list later
        }
        else {
            //we've gotten down to a regular prim.  Break loop and return list
            return avs;
        }
    }
    //there must not have been anyone seated.  Shouldn't ever get here but LSL doesn't know that and wants a return value
    return [];
}

integer RandomUniqueChannel() {
    integer out = llRound(llFrand(10000000)) + 100000;
    if (out == Channel) {
        out = RandomUniqueChannel();
    }
    return out;
}

Dialog(key recipient, string prompt, list menuitems, list utilitybuttons, integer page, key id, string path) {
    prompt = Utf8Trim(prompt, 483);
    string thisprompt = prompt + "(Timeout in 60 seconds.)\n";
    list buttons;
    list currentitems;
    integer numitems = llGetListLength(menuitems + utilitybuttons);
    integer start;
    integer mypagesize;
    if (llList2CSV(utilitybuttons) != "") {
        mypagesize = PAGE_SIZE - llGetListLength(utilitybuttons);
    }
    else{
        mypagesize = PAGE_SIZE;
    }

    //slice the menuitems by page
    if (numitems > PAGE_SIZE) {
        mypagesize--;//we'll use one slot for the MORE button, so shrink the page accordingly
        start = page * mypagesize;
        integer end = start + mypagesize - 1;
        //multi page menu
        currentitems = llList2List(menuitems, start, end);
    }
    else {
        start = 0;
        currentitems = menuitems;
    }
    
    integer stop = llGetListLength(currentitems);
    integer n;
    for (n = 0; n < stop; n++) {
        string name = llList2String(menuitems, start + n);
        buttons += [name];
    }
    buttons = SanitizeButtons(buttons);
    utilitybuttons = SanitizeButtons(utilitybuttons);

    integer menusIndex = llListFindList(Menus, [recipient]);
    if(menusIndex >= 0) {
        Menus = RemoveMenuStride(Menus, menusIndex);
    }
    if(!~Listener) {
        Listener = llListen(Channel, "", NULL_KEY, "");
        llSetTimerEvent(REPEAT);
    }
    if (numitems > PAGE_SIZE) {
        llDialog(recipient, thisprompt, PrettyButtons(buttons, utilitybuttons + [MORE]), Channel);
    }
    else {
        llDialog(recipient, thisprompt, PrettyButtons(buttons, utilitybuttons), Channel);
    }
    integer ts = -1;
    if (llListFindList(Avs, [recipient]) == -1) {
        ts = llGetUnixTime();
    }

    Menus += [recipient, id, ts, prompt, llDumpList2String(menuitems, "|"), llDumpList2String(utilitybuttons, "|"), page, path];
}

list SanitizeButtons(list in) {
    integer length = llGetListLength(in);
    integer n;
    for (n = length - 1; n >= 0; n--) {
        //trim it to avoid shouting on Debug Channel
        string currentButton=Utf8Trim(llList2String(in, n), 24);
        if(currentButton) {
            in = llListReplaceList(in, [currentButton], n, n);
        }
        else {
            in = llDeleteSubList(in, n, n);
        }
    }
    return in;
}

list PrettyButtons(list options, list utilitybuttons) {
    //returns a list formatted to that "options" will start in the top left of a dialog, and "utilitybuttons" will start in the bottom right
    list spacers;
    list combined = options + utilitybuttons;
    while (llGetListLength(combined) % 3 != 0 && llGetListLength(combined) < 12) {
        spacers += [BLANK];
        combined = options + spacers + utilitybuttons;
    }
    
    list out = llList2List(combined, 9, 11);
    out += llList2List(combined, 6, 8);
    out += llList2List(combined, 3, 5);
    out += llList2List(combined, 0, 2);
    return out;
}


list RemoveMenuStride(list menu, integer index) {
    //tell this function the menu you wish to remove, identified by list index
    //it will remove the menu's entry from the list, and return the new list
    //should be called in the listen event, and on menu timeout    
    return llDeleteSubList(menu, index, index + STRIDE_LENGTH - 1);
}

CleanList() {
    debug("cleaning list");
    //loop through Menus, check their start times against current time, remove any that are more than <timeout> seconds old
    //start at end of list and loop down so that indexes don't get messed up as we remove items
    integer length = llGetListLength(Menus);
    integer n;
    for (n = length - STRIDE_LENGTH; n >= 0; n -= STRIDE_LENGTH) {
        integer starttime = llList2Integer(Menus, n + 2);
        debug("starttime: " + (string)starttime);
        if (starttime == -1) {  
            //menu was for seated av.  close if they're not seated anymore
            key av = (key)llList2String(Menus, n);
            if (llListFindList(Avs, [av]) == -1) {
                debug("mainmenu stood");
                Menus = RemoveMenuStride(Menus, n);
            }
        }
        else {
            //was a plain old non-seated menu, most likely for owner.  Do timeouts normally
            integer age = llGetUnixTime() - starttime;
            if (age > TIMEOUT) {
                debug("mainmenu timeout");
                key id = llList2Key(Menus, n + 1);
                llMessageLinked(LINK_SET, DIALOG_TIMEOUT, "", id);
                Menus = RemoveMenuStride(Menus, n);
            }
        }
    }
}

debug(string str) {
    //llOwnerSay(llGetScriptName() + ": " + str);
}

default {
    on_rez(integer param) {
        llResetScript();
    }

    state_entry() {
        Channel = RandomUniqueChannel();
        Avs = SeatedAvs();
    }
    
    changed(integer change) {
        if (change & CHANGED_LINK) {
            Avs = SeatedAvs();
            //loop through dialogs and close any for avs that aren't seated.  except for obj owner
        }
    }

    link_message(integer sender, integer num, string str, key id) {
        if (num == MEMORY_USAGE) {
            llSay(0,"Memory Used by " + llGetScriptName() + ": " + (string)llGetUsedMemory() + " of " + (string)llGetMemoryLimit() + ", Leaving " + (string)llGetFreeMemory() + " memory free.");
        }
        else if (num == DIALOG) {
            //give a dialog with the options on the button labels
            //str will be pipe-delimited list with rcpt|prompt|page|backtick-delimited-list-buttons|backtick-delimited-utility-buttons
            debug(str);
            list params = llParseStringKeepNulls(str, ["|"], []);
            key rcpt = (key)llList2String(params, 0);
            string prompt = llList2String(params, 1);
            integer page = (integer)llList2String(params, 2);
            string path = llList2String(params, 5);
            list lbuttons = llParseStringKeepNulls(llList2String(params, 3), ["`"], []);
            list ubuttons = llParseStringKeepNulls(llList2String(params, 4), ["`"], []);
            Dialog(rcpt, prompt, lbuttons, ubuttons, page, id, path);
        }
    }

    listen(integer channel, string name, key id, string message) {
        integer menuindex = llListFindList(Menus, [id]);
        if (~menuindex) {
            key menuid = llList2Key(Menus, menuindex + 1);
            string prompt = llList2String(Menus, menuindex + 3);
            list items = llParseStringKeepNulls(llList2String(Menus, menuindex + 4), ["|"], []);
            list ubuttons = llParseStringKeepNulls(llList2String(Menus, menuindex + 5), ["|"], []);
            integer page = llList2Integer(Menus, menuindex + 6);
            string path = llList2String(Menus, menuindex + 7);
            Menus = RemoveMenuStride(Menus, menuindex);
            if (message == MORE) {
                debug((string)page);
                //increase the page num and give new menu
                page++;
                integer thispagesize = PAGE_SIZE - llGetListLength(ubuttons) - 1;
                if (page * thispagesize > llGetListLength(items)) {
                    page = 0;
                }
                Dialog(id, prompt, items, ubuttons, page, menuid, path);
            }
            else if (message == BLANK) {
                //give the same menu back
                Dialog(id, prompt, items, ubuttons, page, menuid, path);
            }
            else {
                llMessageLinked(LINK_SET, DIALOG_RESPONSE, (string)page + "|" + message + "|" + (string)id + "|" + path, menuid);
            }
        }
    }
    
    timer() {
        CleanList();
        
        //if list is empty after that, then stop timer
        
        if (!llGetListLength(Menus)) {
            llListenRemove(Listener);
            Listener = -1;
            llSetTimerEvent(0.0);
        }
    }
}
