/* authnz.c: authentication and authorization functions
 *
 * Copyright (C) 2006-2014 cgit Development Team <cgit@lists.zx2c4.com>
 *
 * Licensed under GNU General Public License v2
 *   (see COPYING for full license text)
 */

#include "cgit.h"
#include <stdio.h>

void open_authnz_filter(const char *function, const char *repo, const char *refname)
{
	if (!ctx.cfg.auth_filter) {
		return;
	}

	cgit_open_filter(ctx.cfg.auth_filter, function,
		ctx.env.http_cookie ? ctx.env.http_cookie : "",
		ctx.env.request_method ? ctx.env.request_method : "",
		ctx.env.query_string ? ctx.env.query_string : "",
		ctx.env.http_referer ? ctx.env.http_referer : "",
		ctx.env.path_info ? ctx.env.path_info : "",
		ctx.env.http_host ? ctx.env.http_host : "",
		ctx.env.https ? ctx.env.https : "",
		ctx.env.http_remote_user ? ctx.env.http_remote_user : "",
		repo ? repo :"",
		refname ? refname :"",
		ctx.qry.head ? ctx.qry.head : "",
		ctx.qry.page ? ctx.qry.page : "",
		ctx.qry.url ? ctx.qry.url : "",
		"");

	return;
}

void open_authnz_repo(const char *function, const char *repo)
{
	return open_authnz_filter(function, repo, ctx.qry.head);
}

void open_authnz_refname(const char *function, const char *refname)
{
	return open_authnz_filter(function, ctx.qry.repo, refname);
}

void open_authnz_commit(const char *function, const char *sha1)
{
	return open_authnz_filter(function, ctx.qry.repo, sha1);
}

int close_authnz_filter(void)
{
        if (!ctx.cfg.auth_filter) {
                return 1;
        }

        return cgit_close_filter(ctx.cfg.auth_filter);
}

/* Generic function for all repository authorization beacons */
int valid_authnz_for_repo(const char *repo)
{
	int authorized;
	open_authnz_repo("authorize-repo", repo);
	authorized = close_authnz_filter();

	return authorized;
}

/* Generic function for all refname authorization beacons */
int valid_authnz_for_refname(const char *refname)
{
	int must_free_refname = 0;

	refname = disambiguate_ref(refname, &must_free_refname);

	int authorized;
	open_authnz_refname("authorize-ref", refname);
	authorized = close_authnz_filter();

	if (must_free_refname)
		free((char*) refname);

	return authorized;
}

/* Generic function for all commit authorization beacons */
int valid_authnz_for_commit(struct commit *commit)
{
	int authorized;
	open_authnz_commit("authorize-commit", sha1_to_hex(commit->object.sha1));
	authorized = close_authnz_filter();

	return authorized;
}
