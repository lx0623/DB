#ifndef SESSION_TRACKER_INCLUDED
#define SESSION_TRACKER_INCLUDED
#include "m_string.h"
#include "protocol.h"

class THD;
enum enum_session_tracker
{
  SESSION_SYSVARS_TRACKER,                       /* Session system variables */
  CURRENT_SCHEMA_TRACKER,                        /* Current schema */
  SESSION_STATE_CHANGE_TRACKER,
  SESSION_GTIDS_TRACKER,                         /* Tracks GTIDs */
  TRANSACTION_INFO_TRACKER                       /* Transaction state */
};

#define SESSION_TRACKER_END CURRENT_SCHEMA_TRACKER

/**
  State_tracker
  -------------
  An abstract class that defines the interface for any of the server's
  'session state change tracker'. A tracker, however, is a sub- class of
  this class which takes care of tracking the change in value of a part-
  icular session state type and thus defines various methods listed in this
  interface. The change information is later serialized and transmitted to
  the client through protocol's OK packet.

  Tracker system variables :-
  A tracker is normally mapped to a system variable. So in order to enable,
  disable or modify the sub-entities of a tracker, the user needs to modify
  the respective system variable either through SET command or via command
  line option. As required in system variable handling, this interface also
  includes two functions to help in the verification of the supplied value
  (ON_CHECK) and the updation (ON_UPDATE) of the tracker system variable,
  namely - check() and update().
*/

class State_tracker
{
protected:
  /** Is tracking enabled for a particular session state type ? */
  bool m_enabled;

  /** Has the session state type changed ? */
  bool m_changed;

public:
  /** Constructor */
  State_tracker() : m_enabled(false), m_changed(false)
  {}

  /** Destructor */
  virtual ~State_tracker()
  {}

  /** Getters */
  bool is_enabled() const
  { return m_enabled; }

  bool is_changed() const
  { return m_changed; }

  /** Called in the constructor of THD*/
  // virtual bool enable(THD *thd)= 0;

  /** To be invoked when the tracker's system variable is checked (ON_CHECK). */
  // virtual bool check(THD *thd, set_var *var)= 0;

  /** To be invoked when the tracker's system variable is updated (ON_UPDATE).*/
  // virtual bool update(THD *thd)= 0;

  /** Store changed data into the given buffer. */
  virtual bool store(THD *thd, String &buf)= 0;

  /** Mark the entity as changed. */
  virtual void mark_as_changed(THD *thd, LEX_CSTRING *name)= 0;

  virtual void claim_memory_ownership()
  {}
};

/**
  Session_tracker
  ---------------
  This class holds an object each for all tracker classes and provides
  methods necessary for systematic detection and generation of session
  state change information.
*/

class Session_tracker
{
private:
  State_tracker *m_trackers[SESSION_TRACKER_END + 1];

  /* The following two functions are private to disable copying. */
  /** Copy constructor */
  Session_tracker(Session_tracker const &other)
  {
    DBUG_ASSERT(0);
  }

  /** Copy assignment operator */
  Session_tracker& operator= (Session_tracker const &rhs)
  {
    DBUG_ASSERT(0);
    return *this;
  }

public:

  /** Constructor */
  Session_tracker()
  {}

  /** Destructor */
  ~Session_tracker()
  {
  }
  /**
    Initialize Session_tracker objects and enable them based on the
    tracker_xxx variables' value that the session inherit from global
    variables at the time of session initialization (see plugin_thdvar_init).
  */
  void init(/*const CHARSET_INFO *char_set*/);
  // void enable(THD *thd);
  // bool server_boot_verify(const CHARSET_INFO *char_set, LEX_STRING var_list);

  /** Returns the pointer to the tracker object for the specified tracker. */
  State_tracker *get_tracker(enum_session_tracker tracker) const;

  /** Checks if m_enabled flag is set for any of the tracker objects. */
  bool enabled_any();

  /** Checks if m_changed flag is set for any of the tracker objects. */
  bool changed_any();

  /**
    Stores the session state change information of all changes session state
    type entities into the specified buffer.
  */
  void store(THD *thd, String &main_buf);
  void deinit()
  {
    for (int i= 0; i <= SESSION_TRACKER_END; i ++)
      delete m_trackers[i];
  }

  // void claim_memory_ownership();
};


#endif