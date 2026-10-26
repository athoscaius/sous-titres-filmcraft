// Use launchd's structured local API: credentials never become process arguments.
#include <launch.h>
#include <errno.h>
int FilmCraftSetSessionEnvironment(const char *port, const char *token) {
    launch_data_t request=launch_data_alloc(LAUNCH_DATA_DICTIONARY);
    launch_data_t environment=launch_data_alloc(LAUNCH_DATA_DICTIONARY);
    if(!request||!environment) {if(request)launch_data_free(request);if(environment)launch_data_free(environment);return ENOMEM;}
    launch_data_dict_insert(environment,launch_data_new_string(port),"FILMCRAFT_CONTROL_PORT");
    launch_data_dict_insert(environment,launch_data_new_string(token),"FILMCRAFT_CONTROL_TOKEN");
    launch_data_dict_insert(request,environment,"SetUserEnvironment");
    launch_data_t reply=launch_msg(request);
    int result=reply ? (launch_data_get_type(reply)==LAUNCH_DATA_ERRNO ? launch_data_get_errno(reply):EPROTO):errno;
    if(reply)launch_data_free(reply);
    launch_data_free(request);
    return result;
}
