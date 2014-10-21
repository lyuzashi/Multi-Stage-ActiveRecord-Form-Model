A component of a larger project. Handles a multi-page form and collates various associated models which each include several records.

The complexity of these Ruby classes is due to the dynamic nature of the project they are a part of. 

The goal was a completely editable quiz and user details form for multiple campaigns run by the same app.  
Administrators could create their own set of multiple choice, short and long answer questions which each user would answer over multiple pages.  

The entire class is serializable for storage in a database-backed cookie store while the user is navigating between pages.

Rails validators are meta-programmed based on the fields which an administrator set up with their own interface. 

Common constraints and required fields are also included to ensure at least a minimal set of data is collected.  
The user is always asked to log in to Facebook as part of their journey.