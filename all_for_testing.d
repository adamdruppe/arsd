/++
	This is a dummy module just used to test every active file in the collection.

	Do not use it for anything else.
+/
module arsd.all_for_testing;

import arsd.apng;
import arsd.archive;
version(linux) import arsd.argon2; // not implemented on other OS
// import arsd.audio; // D1 or 2.098
import arsd.blendish;
import arsd.bmp;
import arsd.calendar;
import arsd.cgi;
import arsd.characterencodings;
import arsd.cidr;
import arsd.cli;
import arsd.color;
import arsd.com;
import arsd.comhelpers;
import arsd.conv;
import arsd.core;
import arsd.csv;
import arsd.curl;
import arsd.database;
import arsd.database_generation;
import arsd.dbus;
import arsd.dds;
import arsd.declarativeloader;
import arsd.discord;
import arsd.docs.dev_philosophy;
import arsd.docs.general_concepts;
import arsd.docs;
import arsd.docx;
import arsd.dom;
import arsd.email;
// import arsd.engine; // D1 or 2.098
import arsd.english;
import arsd.eventloop;
// import arsd.exception; // deprecated
import arsd.fibersocket;
import arsd.file;
import arsd.game;
import arsd.gamehelpers;
import arsd.gpio;
import arsd.hmac;
import arsd.html;
import arsd.htmltotext;
// import arsd.htmlwidget; // requires special version of dom.d and obsolete anyway, use my other browser stuff instead like jambrowser
import arsd.http;
import arsd.http2;
import arsd.ico;
import arsd.image;
import arsd.imageresize;
import arsd.ini;
import arsd.jni;
import arsd.joystick;
import arsd.jpeg;
import arsd.jpg;
import arsd.jsvar;
import arsd.mailserver;
import arsd.mangle;
import arsd.markdown;
import arsd.midi;
import arsd.midiplayer;
import arsd.minigui;
import arsd.minigui_addons.color_dialog;
import arsd.minigui_addons.datetime_picker;
import arsd.minigui_addons.keyboard_palette_widget;
import arsd.minigui_addons.nanovega;
import arsd.minigui_addons;
import arsd.minigui_addons.terminal_emulator_widget;
import arsd.minigui_addons.webview;
import arsd.minigui_xml;
import arsd.mp3;
import arsd.mssql;
import arsd.mvd;
import arsd.mysql;
import arsd.nanovega;
import arsd.nukedopl3;
import arsd.oauth;
import arsd;
import arsd.pcx;
import arsd.pixmappaint;
import arsd.pixmappresenter;
import arsd.pixmaprecorder;
import arsd.png;
import arsd.postgres;
import arsd.pptx;
import arsd.qrcode;
import arsd.querygenerator;
import arsd.random;
import arsd.rpc;
import arsd.rss;
import arsd.rtf;
// import arsd.rtud; // totally obsolete
// import arsd.screen; // D1 or 2.098
import arsd.script;
import arsd.sha;
import arsd.simpleaudio;
import arsd.simpledisplay;
import arsd.sqlite;
// import arsd.sslsocket; // obsolete
// import arsd.stb_truetype; // obsolete
import arsd.string;
import arsd.svg;
import arsd.targa;
import arsd.terminal;
import arsd.terminalemulator;
import arsd.textlayouter;
import arsd.ttf;
import arsd.uda;
import arsd.uri;
import arsd.vorbis;
import arsd.wav;
import arsd.web;
import arsd.webtemplate;
import arsd.webview;
import arsd.wmutil;
import arsd.xlsx;
import arsd.xwindows;
import arsd.zip;
