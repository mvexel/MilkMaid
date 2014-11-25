//
//  MilkMaidWindowController.m
//  MilkMaid
//
//  Created by Gregamel on 2/28/10.
//  Copyright 2010 JGA. All rights reserved.
//

#import "MilkMaidWindowController.h"

#define TOKEN @"Token"
#define LAST_LIST @"LastList"
#define TAGS @"Tags"

@implementation MilkMaidWindowController

-(void)awakeFromNib {
	[self.window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
	NSString *apiKey = @"1734ba9431007c2242b6865a69940aa5";
	NSString *secret = @"72d1c12ffb26e759";
	
	priority1Image = [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"priority1" ofType:@"png"]];
	priority2Image = [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"priority2" ofType:@"png"]];
	priority3Image = [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"priority3" ofType:@"png"]];
	
	id tags = [[NSUserDefaults standardUserDefaults] objectForKey:TAGS];
	if (tags) {
		tagList = [[NSMutableArray alloc] initWithArray:[(NSMutableArray*)tags sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]];

	} else {
		tagList = [[NSMutableArray alloc] init];
	}

	
	[progress setForeColor:[NSColor whiteColor]];
	[progress startAnimation:nil];
	
	[taskTable setDelegate:self];
	[taskTable setDataSource:self];
	//return;
	rtmController = [[EVRZRtmApi alloc] initWithApiKey:apiKey andApiSecret:secret];

	[NSThread detachNewThreadSelector:@selector(checkToken) toTarget:self withObject:nil];
}

- (void)checkToken {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString * token = [[NSUserDefaults standardUserDefaults] objectForKey:TOKEN];
	
	if (token) {
		rtmController.token = token;
		NSDictionary *data = [rtmController dataByCallingMethod:@"rtm.auth.checkToken" andParameters:[[NSDictionary alloc]init] withToken:YES];
		if ([[data objectForKey:@"stat"] isEqualToString:@"ok"]) {
			timeline = [rtmController timeline];
			[timeline retain];
			[self getLists];
			//[self performSelectorOnMainThread:@selector(getLists) withObject:nil waitUntilDone:NO];
		} else {
			[self getAuthToken];
		}
		
	} else {
		[self getAuthToken];
	}
	[pool release];
}

-(void)getAuthToken {
	NSString *frob = [rtmController frob];
	NSString *url = [rtmController authUrlForPerms:@"delete" withFrob:frob];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
	[self performSelectorOnMainThread:@selector(showAuthMessage:) withObject:frob waitUntilDone:NO];
	//[self showAuthMessage:frob];	
}

-(void)showAuthMessage:(NSString*)frob {
	NSAlert *alert = [[NSAlert alloc] init];
	[alert addButtonWithTitle:@"Done"];
	[alert addButtonWithTitle:@"Cancel"];
	[alert setMessageText:@"Accept Permissions"];
	[alert setInformativeText:@"A browser has been opened. Please press the \"OK, I'll allow it\" button then press the Done button below."];
	[alert setAlertStyle:NSWarningAlertStyle];
	
	if ([alert runModal] == NSAlertFirstButtonReturn) {
		NSString *token = [rtmController tokenWithFrob:frob];
		rtmController.token = token;
		[[NSUserDefaults standardUserDefaults] setObject:token forKey:TOKEN];
		[self performSelectorOnMainThread:@selector(getLists) withObject:nil waitUntilDone:NO];
		//[self doneLoading];
		
		
	}
	[alert release];
}

-(RTMSearch*)getCurrentList {
	return [lists objectAtIndex:[listPopUp indexOfSelectedItem]-1];
}

- (void)getLists {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *data = [rtmController dataByCallingMethod:@"rtm.lists.getList" andParameters:[[NSDictionary alloc]init] withToken:YES];
	lists = [RTMHelper getLists:data];
	for (RTMSearch *list in lists) {
		[listPopUp addItemWithTitle:list.title];
	}
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"tagsInDropDown"]) {
		for (NSString *tag in tagList) {
			[self addTagToDropDown:tag];
		}
	}
	[lists retain];
	//[data release];
	[pool release];
	[progress setHidden:YES];
	[self performSelectorOnMainThread:@selector(selectLast) withObject:nil waitUntilDone:NO];
}

-(void)setLoadLastList:(BOOL)load {
	loadLastList = load;
}

-(void)selectLast {
	if (loadLastList) {
		NSString *lastList = [[NSUserDefaults standardUserDefaults] objectForKey:LAST_LIST];
		if (lastList) {
			[listPopUp selectItemWithTitle:lastList];
			[self listSelected:nil];
		}
	}
}

-(void)listSelected:(id)sender {
	
	NSInteger selectedIndex = [listPopUp indexOfSelectedItem];
	selectedIndex--;
	if (selectedIndex > -1) {
		RTMSearch *selectedList = [self getCurrentList];
		if (!lastListTitle || ![selectedList.title isEqualToString:lastListTitle]) {
			
			[[taskScroll contentView] scrollToPoint:NSMakePoint(0, 0)];
			if (![selectedList.searchType isEqualToString:@"search"]) {
				[[NSUserDefaults standardUserDefaults] setObject:selectedList.title forKey:LAST_LIST];
			}
			lastListTitle = selectedList.title;
			[NSThread detachNewThreadSelector:@selector(getTasks) toTarget:self withObject:nil];
			
		}
	}
}

-(void)getTasks {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[progress setHidden:NO];

	NSDictionary *data = [rtmController dataByCallingMethod:@"rtm.tasks.getList" andParameters:[[self getCurrentList] searchParams] withToken:YES];
	
	RTMHelper *rtmHelper = [[RTMHelper alloc] init];
	
	tasks = [rtmHelper getFlatTaskList:data];
	
	[self performSelectorOnMainThread:@selector(loadTaskData) withObject:nil waitUntilDone:NO];
	
	[tasks retain];
	[rtmHelper release];
	[pool release];
	[progress setHidden:YES];
}


-(void)menuRefresh:(id)sender {
	[NSThread detachNewThreadSelector:@selector(getTasks) toTarget:self withObject:nil];
}

-(void)loadTaskData {
	//NSLog(@"%@", tasks);
	[self.window setTitle:[NSString stringWithFormat:@"MilkMaid (%d)", [tasks count]]];
	if ([tasks count] != 0) {
		[[[NSApplication sharedApplication] dockTile] setBadgeLabel:[[NSNumber numberWithInt:[tasks count]] stringValue]];
	} else {
		[[[NSApplication sharedApplication] dockTile] setBadgeLabel:@""];
	}
	for (NSDictionary *task in tasks) {
		[self addGlobalTags:[task objectForKey:@"tags"]];
	}
    // sorting of the array with priority
    [tasks sortUsingComparator:^(NSDictionary *task1, NSDictionary *task2){
        NSString *pri1 = [task1 objectForKey:@"priority"];
        NSString *pri2 = [task2 objectForKey:@"priority"];
        return [pri1 caseInsensitiveCompare:pri2];
        
    }] ;
	[taskTable reloadData];
	
}

-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return [tasks count];
}



-(id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	//check type of cell
	
	id cell = [tableColumn dataCellForRow:row];
	//NSLog(@"%@", cell);
	if ([cell isMemberOfClass:[BWTransparentCheckboxCell class]]) {
		return [NSNumber numberWithInteger:NSOffState];
	} else if ([cell isMemberOfClass:[NSImageCell class]]) {
		NSDictionary *task = [tasks objectAtIndex:row];
		NSString *pri = [task objectForKey:@"priority"];
		if ([pri isEqualToString:@"1"]) {
			return priority1Image;
		} else if ([pri isEqualToString:@"2"]) {
			return priority2Image;
		} else if ([pri isEqualToString:@"3"]) {
			return priority3Image;
		} else {
			return nil;
		}
	} else {//if ([cell isMemberOfClass:[BWTransparentTableViewCell class]]) {
		NSDictionary *task = [tasks objectAtIndex:row];
		
		id due = [task objectForKey:@"due"];
		if ([due isKindOfClass:[NSDate class]]) {
			[cell setAlternate2Text:[due relativeFormattedDateOnly]];
			if ([due isPastDate] || [[NSDate date] isEqualToDate:due]) {
				[cell setBold:YES];
			} 
		} else {
			[cell setAlternate2Text:@""];
			[cell setBold:NO];
		}
		
		[cell setAlternateText:[[task objectForKey:@"tags"] componentsJoinedByString:@","]];

		return [task objectForKey:@"name"];
	}
	
}

-(void)addTagToDropDown:(NSString*)tagName {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"tagsInDropDown"]) {
		NSString *tag = [NSString stringWithFormat:@"#%@", tagName];
		RTMSearch *search = [[RTMSearch alloc] 
							 initWithTitle:tag
							 searchType:@"tag" 
							 searchParams:[[NSDictionary alloc] initWithObjectsAndKeys:[NSString stringWithFormat:@"tag:%@ and status:incomplete",tagName], @"filter", nil]
							 addAttributes:tag];
		[lists addObject:search];
		[listPopUp addItemWithTitle:tag];
	}
}

-(void)addGlobalTags:(NSArray*)tags {
	for (NSString *tag in tags) {
		if (![tagList containsObject:tag]){
			[tagList addObject:tag];
			[self addTagToDropDown:tag];
		}
	}
	[tagList retain];
	[[NSUserDefaults standardUserDefaults] setObject:tagList forKey:TAGS];
}



-(void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	NSDictionary *task = [tasks objectAtIndex:row];
	NSDictionary *params = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:timeline, [task objectForKey:@"list_id"], [task objectForKey:@"taskseries_id"], [task objectForKey:@"task_id"], nil] 
														 forKeys:[NSArray arrayWithObjects:@"timeline", @"list_id", @"taskseries_id", @"task_id", nil]];
	
	[tasks removeObject:task];
	[NSThread detachNewThreadSelector:@selector(completeTask:) toTarget:self withObject:params];
	[self loadTaskData];
}

-(void)completeTask:(NSDictionary *)taskInfo {
	[progress setHidden:NO];
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *data = [rtmController dataByCallingMethod:@"rtm.tasks.complete" andParameters:taskInfo withToken:YES];
	[pool release];
	[progress setHidden:YES];
}

-(void)menuAddTask:(id)sender {
	
	if (!singleInputWindowController)
		singleInputWindowController = [[SingleInputWindowController alloc] initWithWindowNibName:@"SingleInput"];
	[singleInputWindowController setButtonText:@"Add Task"];
	NSWindow *sheet = [singleInputWindowController window];
	[NSApp beginSheet:sheet modalForWindow:self.window modalDelegate:self 
	   didEndSelector:@selector(closeAddTaskSheet:returnCode:contextInfo:) contextInfo:nil];
}

-(void)closeAddTaskSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
	[sheet orderOut:self];
	if (returnCode == 1) {
		NSString *task = [singleInputWindowController text];
		[NSThread detachNewThreadSelector:@selector(addTask:) toTarget:self withObject:task];
	}
	
}

-(void)addTask:(NSString*)task {
	[progress setHidden:NO];
	RTMSearch *currentList = [self getCurrentList];
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	if (currentList.addAttributes)
		task = [NSString stringWithFormat:@"%@ %@", task, currentList.addAttributes];
	
	NSMutableDictionary *orgParams = [[NSMutableDictionary alloc] initWithObjects:[NSArray arrayWithObjects:timeline, task, @"1", nil]
																	   forKeys:[NSArray arrayWithObjects:@"timeline", @"name", @"parse", nil]];
    NSMutableDictionary *params = [orgParams mutableCopy];
	if (currentList.addParams) {
		[params addEntriesFromDictionary:currentList.addParams];
	}
    NSDictionary * returnValues= [rtmController dataByCallingMethod:@"rtm.tasks.add" andParameters:params withToken:YES];
    NSDictionary* error = [returnValues objectForKey:@"err"];
    if (error ) {
        // we have an error!
        if ([(NSString*)[error valueForKey:@"code"] isEqualToString:@"4020"]) {
            //this is the error code used for  @"Cannot add task to a Smart List.", hence we need to kill the list add
            NSDictionary * secondReturn= [rtmController dataByCallingMethod:@"rtm.tasks.add" andParameters:orgParams withToken:YES];
            NSDictionary* error2 = [secondReturn objectForKey:@"err"];
            if (error2) {
                NSLog(@"Error 2: %@",error2);
            }
        }
    }
	[self getTasks];
	[pool release];
	[progress setHidden:YES];
}

-(void)addTasks:(NSArray*)newTasksArray {
	[progress setHidden:NO];
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSArray *newTasks = [newTasksArray objectAtIndex:0];
	NSString *globalAttributes = [newTasksArray objectAtIndex:1];
	RTMSearch *currentSearch = [self getCurrentList];
	for (NSString *t in newTasks) {
		NSString *globalTaskAttributes = (currentSearch.addAttributes)?currentSearch.addAttributes:@"";
		NSString *taskName = [NSString stringWithFormat:@"%@ %@ %@", t, globalTaskAttributes, globalAttributes];
		NSMutableDictionary *params = [[NSMutableDictionary alloc] initWithObjects:[NSArray arrayWithObjects:timeline, taskName, @"1", nil] 
																		   forKeys:[NSArray arrayWithObjects:@"timeline", @"name", @"parse", nil]];
		
		if (currentSearch.addParams) {
			[params addEntriesFromDictionary:currentSearch.addParams];
		}
		[rtmController dataByCallingMethod:@"rtm.tasks.add" andParameters:params withToken:YES];
		
	}
	[self getTasks];
	[pool release];
	[progress setHidden:YES];
	
}

-(void)menuShowLists:(id)sender {
	[listPopUp performClick:self];
}

-(void)menuPriority:(id)sender {
	NSInteger rowIndex = [taskTable selectedRow];
	if (rowIndex == -1)
		return;
	NSDictionary *task = [tasks objectAtIndex:rowIndex];
	
	NSDictionary *params = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:timeline, [task objectForKey:@"list_id"], [task objectForKey:@"taskseries_id"], [task objectForKey:@"task_id"], [sender title], nil] 
														 forKeys:[NSArray arrayWithObjects:@"timeline", @"list_id", @"taskseries_id", @"task_id", @"priority", nil]];
	[NSThread detachNewThreadSelector:@selector(setPriority:) toTarget:self withObject:params];
}

-(void)setPriority:(NSDictionary*)params {
	[progress setHidden:NO];
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[rtmController dataByCallingMethod:@"rtm.tasks.setPriority" andParameters:params withToken:YES];
	
	[self getTasks];
	[pool release];
	[progress setHidden:YES];
}

-(void)menuDueDate:(id)sender {
	NSInteger rowIndex = [taskTable selectedRow];
	if (rowIndex == -1)
		return;
	NSDictionary *task = [tasks objectAtIndex:rowIndex];
	
	NSDictionary *params = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:timeline, [task objectForKey:@"list_id"], [task objectForKey:@"taskseries_id"], [task objectForKey:@"task_id"], [sender title], @"1", nil] 
														 forKeys:[NSArray arrayWithObjects:@"timeline", @"list_id", @"taskseries_id", @"task_id", @"due", @"parse", nil]];
	[NSThread detachNewThreadSelector:@selector(setDueDate:) toTarget:self withObject:params];
}

-(void)setDueDate:(NSDictionary*)params {
	[progress setHidden:NO];
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[rtmController dataByCallingMethod:@"rtm.tasks.setDueDate" andParameters:params withToken:YES];
	
	[self getTasks];
	[pool release];
	[progress setHidden:YES];
}

-(void)menuPostponeTask:(id)sender {
	NSInteger rowIndex = [taskTable selectedRow];
	if (rowIndex == -1)
		return;
	NSDictionary *task = [tasks objectAtIndex:rowIndex];
	
	NSDictionary *params = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:timeline, [task objectForKey:@"list_id"], [task objectForKey:@"taskseries_id"], [task objectForKey:@"task_id"], nil] 
														 forKeys:[NSArray arrayWithObjects:@"timeline", @"list_id", @"taskseries_id", @"task_id", nil]];
	[NSThread detachNewThreadSelector:@selector(postponeTask:) toTarget:self withObject:params];
}

-(void)postponeTask:(NSDictionary*)params {
	[progress setHidden:NO];
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[rtmController dataByCallingMethod:@"rtm.tasks.postpone" andParameters:params withToken:YES];
	
	[self getTasks];
	[pool release];
	[progress setHidden:YES];
}

-(void)menuDeleteTask:(id)sender {
	NSInteger rowIndex = [taskTable selectedRow];
	if (rowIndex == -1)
		return;
	NSDictionary *task = [tasks objectAtIndex:rowIndex];
	
	NSDictionary *params = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:timeline, [task objectForKey:@"list_id"], [task objectForKey:@"taskseries_id"], [task objectForKey:@"task_id"], nil] 
														 forKeys:[NSArray arrayWithObjects:@"timeline", @"list_id", @"taskseries_id", @"task_id", nil]];
	[NSThread detachNewThreadSelector:@selector(deleteTask:) toTarget:self withObject:params];
}

-(void)deleteTask:(NSDictionary*)params {
	[progress setHidden:NO];
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[rtmController dataByCallingMethod:@"rtm.tasks.delete" andParameters:params withToken:YES];
	
	[self getTasks];
	[pool release];
	[progress setHidden:YES];
}

-(void)menuSearch:(id)sender {
	if (!singleInputWindowController)
		singleInputWindowController = [[SingleInputWindowController alloc] initWithWindowNibName:@"SingleInput"];
	[singleInputWindowController setButtonText:@"Search"];
	NSWindow *sheet = [singleInputWindowController window];
	[NSApp beginSheet:sheet modalForWindow:self.window modalDelegate:self 
	   didEndSelector:@selector(closeSearchSheet:returnCode:contextInfo:) contextInfo:nil];
}

-(void)search:(NSString*)searchString {
	RTMSearch *search = [[RTMSearch alloc] 
						 initWithTitle:searchString
						 searchType:@"search" 
						 searchParams:[[NSDictionary alloc] initWithObjectsAndKeys:[NSString stringWithFormat:@"(%@) and status:incomplete",searchString], @"filter", nil]
						 addAttributes:nil];
	[lists addObject:search];
	[listPopUp addItemWithTitle:searchString];
	[listPopUp selectItemWithTitle:searchString];
	[self listSelected:nil];
}

-(void)closeSearchSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
	[sheet orderOut:self];
	if (returnCode == 1) {
		NSString *currentSearch = [singleInputWindowController text];
		
		[self search:currentSearch];
		
		//[NSThread detachNewThreadSelector:@selector(searchTasks:) toTarget:self withObject:currentSearch];
	}
	
}

-(void)menuMultiAdd:(id)sender {
	if (!multiAddWindowController)
		multiAddWindowController = [[MultiAddWindowController alloc] initWithWindowNibName:@"MultiAdd"];
	NSWindow *sheet = [multiAddWindowController window];
	[NSApp beginSheet:sheet modalForWindow:self.window modalDelegate:self 
	   didEndSelector:@selector(closeMultiAddSheet:returnCode:contextInfo:) contextInfo:nil];
}

-(void)closeMultiAddSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
	[sheet orderOut:self];
	if (returnCode == 1) {
		NSArray *newTasks = [multiAddWindowController tasks];
		NSString *globalAttributes = [multiAddWindowController globalAttributes];
		[NSThread detachNewThreadSelector:@selector(addTasks:) toTarget:self withObject:[NSArray arrayWithObjects: newTasks,globalAttributes,nil]];
	}
	
}

-(void)menuRenameTask:(id)sender {
	NSInteger rowIndex = [taskTable selectedRow];
	if (rowIndex == -1)
		return;
	NSDictionary *task = [tasks objectAtIndex:rowIndex];
	if (!singleInputWindowController)
		singleInputWindowController = [[SingleInputWindowController alloc] initWithWindowNibName:@"SingleInput"];
	[singleInputWindowController setButtonText:@"Rename"];
	[singleInputWindowController setTextValue:[task objectForKey:@"name"]];
	NSWindow *sheet = [singleInputWindowController window];
	[NSApp beginSheet:sheet modalForWindow:self.window modalDelegate:self 
	   didEndSelector:@selector(closeRenameTaskSheet:returnCode:contextInfo:) contextInfo:nil];
}

-(void)closeRenameTaskSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
	[sheet orderOut:self];
	if (returnCode == 1) {
		NSString *taskName = [singleInputWindowController text];
		NSInteger rowIndex = [taskTable selectedRow];
		if (rowIndex == -1)
			return;
		NSDictionary *task = [tasks objectAtIndex:rowIndex];
		
		NSDictionary *params = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:timeline, [task objectForKey:@"list_id"], [task objectForKey:@"taskseries_id"], [task objectForKey:@"task_id"], taskName,nil] 
															 forKeys:[NSArray arrayWithObjects:@"timeline", @"list_id", @"taskseries_id", @"task_id", @"name", nil]];
		[NSThread detachNewThreadSelector:@selector(renameTask:) toTarget:self withObject:params];
	}
	
}
-(void)renameTask:(NSDictionary*)params {
	[progress setHidden:NO];
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[rtmController dataByCallingMethod:@"rtm.tasks.setName" andParameters:params withToken:YES];
	[self getTasks];
	[pool release];
	[progress setHidden:YES];
}

-(void)menuSetTagsTask:(id)sender {
	NSInteger rowIndex = [taskTable selectedRow];
	if (rowIndex == -1)
		return;
	NSDictionary *task = [tasks objectAtIndex:rowIndex];
	if (!singleInputWindowController)
		singleInputWindowController = [[SingleInputWindowController alloc] initWithWindowNibName:@"SingleInput"];
	[singleInputWindowController setButtonText:@"Set Tags"];
	[singleInputWindowController setTextValue:[[task objectForKey:@"tags"] componentsJoinedByString:@","]];
	NSWindow *sheet = [singleInputWindowController window];
	[NSApp beginSheet:sheet modalForWindow:self.window modalDelegate:self 
	   didEndSelector:@selector(closeSetTagsTaskSheet:returnCode:contextInfo:) contextInfo:nil];
}

-(void)closeSetTagsTaskSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
	[sheet orderOut:self];
	if (returnCode == 1) {
		NSString *tags = [singleInputWindowController text];
		NSInteger rowIndex = [taskTable selectedRow];
		if (rowIndex == -1)
			return;
		NSDictionary *task = [tasks objectAtIndex:rowIndex];
		
		NSDictionary *params = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:timeline, [task objectForKey:@"list_id"], [task objectForKey:@"taskseries_id"], [task objectForKey:@"task_id"], tags,nil] 
															 forKeys:[NSArray arrayWithObjects:@"timeline", @"list_id", @"taskseries_id", @"task_id", @"tags", nil]];
		[NSThread detachNewThreadSelector:@selector(setTagsTask:) toTarget:self withObject:params];
	}
	
}
-(void)setTagsTask:(NSDictionary*)params {
	[progress setHidden:NO];
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[rtmController dataByCallingMethod:@"rtm.tasks.setTags" andParameters:params withToken:YES];
	[self getTasks];
	[pool release];
	[progress setHidden:YES];
}

-(void)menuSetDueTask:(id)sender {
	NSInteger rowIndex = [taskTable selectedRow];
	if (rowIndex == -1)
		return;
	NSDictionary *task = [tasks objectAtIndex:rowIndex];
	if (!singleInputWindowController)
		singleInputWindowController = [[SingleInputWindowController alloc] initWithWindowNibName:@"SingleInput"];
	[singleInputWindowController setButtonText:@"Set Due"];
	[singleInputWindowController setTextValue:[[task objectForKey:@"due"] isKindOfClass:[NSDate class]] ? [[task objectForKey:@"due"] relativeFormattedDateOnly] : @""];
	NSWindow *sheet = [singleInputWindowController window];
	[NSApp beginSheet:sheet modalForWindow:self.window modalDelegate:self 
	   didEndSelector:@selector(closeSetDueTaskSheet:returnCode:contextInfo:) contextInfo:nil];
}

-(void)closeSetDueTaskSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
	[sheet orderOut:self];
	if (returnCode == 1) {
		NSString *due = [singleInputWindowController text];
		NSInteger rowIndex = [taskTable selectedRow];
		if (rowIndex == -1)
			return;
		NSDictionary *task = [tasks objectAtIndex:rowIndex];
		
		NSDictionary *params = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:timeline, [task objectForKey:@"list_id"], [task objectForKey:@"taskseries_id"], [task objectForKey:@"task_id"], due, @"1", nil] 
															 forKeys:[NSArray arrayWithObjects:@"timeline", @"list_id", @"taskseries_id", @"task_id", @"due", @"parse", nil]];
		[NSThread detachNewThreadSelector:@selector(setDueTask:) toTarget:self withObject:params];
	}
	
}
-(void)setDueTask:(NSDictionary*)params {
	[progress setHidden:NO];
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[rtmController dataByCallingMethod:@"rtm.tasks.setDueDate" andParameters:params withToken:YES];
	[self getTasks];
	[pool release];
	[progress setHidden:YES];
}

@end
